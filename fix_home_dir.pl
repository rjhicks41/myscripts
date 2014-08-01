#! /usr/bin/perl 

=head1 NAME

fix_home_dir.pl -- 	script to fix directory ownership and permissions on FAS
			home directories.

=cut

=head1 AUTHOR

	Jim Hicks, Harvard University Information Technology, james_hicks@harvard.edu
	Steve Huff, Harvard University Information Technology, steve_huff@harvard.edu

=head1 SYNOPSIS

	Usage: fix_home_dir.pl <FAS LDAP User ID 1> ... <FAS LDAP User ID N>

=cut

use strict;
use warnings;
use English;
use File::Basename;
use File::stat;
use File::Find;
use File::Find::Rule;
use User::pwent;
use Sys::Syslog qw( :DEFAULT setlogsock);

my ($validuser, $wholegetpwnam);
my ($pw, $nme, $uid, $gid, $gcs, $dir, $shl);
my ($hdmodedef) = 16841;
my ($htmodedef) = 16877;
my ($htmode);

my ($clear_string) = `clear`;
my ($script) = basename($0);
my ($usage) = "Usage: $script <FAS LDAP username>\n";

my ($sudouser) = $ENV{'SUDO_USER'};

# needs to be run as root
if ( $EUID != 0 ) {
	&syslogger('err', "$script must be run as root.  exiting.");
	die "$script must be run as root";
}

# if not running out of sudo, set the sudouser the same as runuser.  
# this is for tidiness.  because of test above, this will always be root.
if (not defined($sudouser) or -z $sudouser) {
	my $runuser = getpwuid($EUID);
	$sudouser = $runuser->name();
}

# test to make sure that a username argument was supplied on the command line
# and die with usage message if none
unless ( @ARGV ) {
	&syslogger('err', "$script requires LDAP username as input. exiting");
        die $usage;
}

# grab username argument from command line
while ( my $fasuser = shift( @ARGV ) ) {
	chomp( $fasuser );

	# test that $fasuser is defined and, if so, get the user's information from LDAP.
	if (not defined($fasuser) or not $fasuser) {
	   die "$usage";
	} else {
	   ( $pw = getpwnam($fasuser) ) or ( &syslogger('err', "$fasuser does not exist in LDAP.  exiting.") and die "$fasuser does not exist.\n$usage\n");
		$nme = $pw->name;
		$uid = $pw->uid;
		$gid = $pw->gid;
		$gcs = $pw->gecos;
		$dir = $pw->dir;
		$shl = $pw->shell;
	}

	# get some information about user's home directory
	my $hdmode = stat($dir)->mode;
	my $hduid = stat($dir)->uid;
	my $hdgid = stat($dir)->gid;


	# require verification of LDAP user or die	

	my $verification = <<VERIFICATION;

Please verify that I have found the correct user:

Username:			$nme
UID:				$uid
GID:				$gid
GECOS:				$gcs
Homedir:			$dir
Shell:				$shl

VERIFICATION

	print $verification;

	printf "$dir permissions:\t\t\t\t%04o\n", $hdmode & 07777;
	print "\n";

	my $fasuserverify = &q_and_a("Is this the user you intended? [yes/no]", qr/yes|no/i);

	# if the LDAP user checks out, continue.
	if ($fasuserverify =~ m/yes/i) {
		print "\nContinuing with FAS LDAP User $nme . . .\n\n";
	} else {
		&nochg;
		die "\n\t\tUnceremonious Exit.\n\n";
	}

	# check home directory ownership and give option to correct, if necessary
	if ($hduid == $uid) {
		print "OK:  $dir is owned by $nme.\n";
		&listfile($dir);
		&nochg;
	} else {
		print "FAIL:  $dir is NOT owned by $nme.\t\t  \n";
		&listfile($dir);
		my $fixown = &q_and_a("\nShall I fix?", qr/yes|no/i);
			if ($fixown =~ m/yes/i) {
			my $rule = File::Find::Rule->maxdepth(1)->start($dir);
			while (defined( my $findmatch = $rule->match)) {
				chown $uid, $gid, $findmatch;
			}
			print "FIXED:  $dir ownership changed to $uid:$gid\n";
			&listfile($dir);
			&syslogger('info', "$sudouser changed $dir ownership to $uid:$gid");
			} else {
				&nochg;
			}
		}

	# check home directory permissions and give option to correct, if necessary
	if ($hdmode == $hdmodedef) {
		print "OK:  $dir permissions are correct.\n";
		&listfile($dir);
		&nochg;
	} else {
		print "FAIL:  $dir permissions are NOT default.\n";
		&listfile($dir);
		my $fixhdmode = &q_and_a("Shall I fix?", qr/yes|no/i);
			if ($fixhdmode =~ m/yes/i) {
			chmod 0711, $dir or die "chmod of $dir FAILED.\n";
			$hdmode = stat($dir)->mode;
			printf "FIXED:  $dir permissions:\t\t\t\t%04o\n", $hdmode & 07777;
			&listfile($dir);
			&syslogger('info', "$sudouser changed $dir permissions to 0711.");
			} else {
				&nochg;
			}
		}
			
	print "\n";
	print "\t\tGAME OVER.\n";
	print "\n";
}

# subroutine definitions

sub q_and_a {
# requests a valid response to a question and returns the answer provided
	my ($question, $valid) = @_;
	print "$question:  ";
	chomp (my $answer = <STDIN>);
	unless( $answer =~ $valid ) {
		print "Please respond with \"Yes\" or \"No\"\n";
		print "\n";
		$answer = &q_and_a($question, $valid);
	}
	return $answer;
}

sub listfile {
# does a unix long listing on a directory taken as input
	my ($listdir) = @_;
	print "\n";
	my @file_ls = map {chomp; $_ } `ls -ld $listdir`;
        print "\t\t@file_ls\n";
	print "\n";
}

sub nochg {
	print "\n";
	print "No changes made.\n";
	print "\n";
}

sub syslogger {
# logs to syslog
	my ($prio, $msg) = @_;
	return unless ($prio =~ /info|err|debug/);

	setlogsock('unix');
	openlog($script, 'pid', 'user');
	syslog($prio, $msg);
	closelog();
}
