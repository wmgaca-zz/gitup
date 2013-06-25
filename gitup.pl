#!/usr/bin/perl

use strict;
use warnings;
use POSIX qw/strftime/;
use feature 'state';
use File::Basename;

my $scriptDir = dirname(__FILE__);
my $gitRootDir = "$scriptDir/git";

my %data = (
	gilbert => {
		source => 'https://github.intel.com/wmgacax/gitup.git',
		dest => 'git@somewhere.else:wmgacax/gitup.git'
	}
);

sub trim {
	(my $s = $_[0]) =~ s/^\s+|\s+$//g;
	return $s;
}

sub exec_ {
	trace("Exec command: $_[0]");

	my $ret = `$_[0]`;
	my @lines = split('\n', $ret);

	foreach (@lines) {
		trace("\$ $_", 4);
	}

	return $ret;
}

sub getTimestamp {
	my ($fancyMode) = @_;
	my $format = "";

	# If any mode given: assume pretty log format, raw otherwise
	if ($fancyMode) {
		$format = '%Y-%m-%d %H:%M:%S';
	} else {
		$format = '%Y%m%d%H%M%S';
	}

	return strftime($format, localtime); 
}

{
	my $logPath = "$scriptDir/gitup.log";
	my $indentSize = 4;

	# Rotate the log file if bigger than 100 MB (100 * 1000 * 1000 B)
	my $logSize = -s "$logPath";
	if ($logSize && $logSize > 10000000000) {
		`mv $logPath $logPath.1`;
	}
	
	# Set up the logger: open log file for writing
	open(my $logFileHandle, ">>$logPath") or die $!;

	sub trace {
		# Print the message to stdout and save to the log file

		my $extraIndentSize = 0;
		if ($_[1] && $_[1] > 0) {
			$extraIndentSize = $_[1];
		}

		my $msg = getTimestamp(1) . " "x($indentSize + $extraIndentSize) . "$_[0]\n";

		print $logFileHandle $msg;
		print $msg;	
	}
}

sub process {
	trace("Start. " . "~"x74);
	trace("");
	trace("Cloning the repository...");

	# Create the root dir if not exists
	unless (-d $gitRootDir) {
		trace("$gitRootDir not found.");
		mkdir $gitRootDir or die $;
	}

	for my $name (sort keys %data) {
		my $source = $data{$name}{source};
		my $destination = $data{$name}{destination};

		my $repoDir = "$gitRootDir/$name";

		# Step 1 -- check if the repository exists
		my $skipUpdateCheck = 0;
		unless (-d $repoDir) {
			trace("Cloning the repository $name from $source...");
			exec_("git clone $source $repoDir");
			$skipUpdateCheck = 1;
		}

		# Step 2 -- go to repository
		chdir($repoDir);

		# Step 3 -- fetch
		exec_("git fetch origin");

		# Step 3 -- get branches
		my @branches = ();
		my @branchesLocal = ();
		foreach (split("\n", exec_("git branch -a"))) {
			my $branch = trim($_);
			if ($branch =~ m/remotes\/origin/) {
				$branch =~ s/remotes\/origin\///g;
				if ($branch =~ m/^(?!HEAD)/) {
					push @branches, $branch;
				}
			} else {
				$branch =~ s/\*//g;
				$branch = trim($branch);
				push @branchesLocal, $branch;
			}
		}

		trace("Remote branches:");
		foreach (@branches) {
			trace("=> $_", 4);
		}

		trace("Local branches:");
		foreach (@branchesLocal) {
			trace("=> $_", 4);
		}
		
		foreach (@branches) {
			trace("Checkout branch origin/$_");

			exec_("git checkout $_");

			# Check for updates
			if (!$skipUpdateCheck) {
				# Check only if branch is present in local branches
				# (so that we know that it was synced before)
				if ("$_" ~~ @branchesLocal) {
					my $cmd = "git log HEAD..origin/$_ --oneline";
					my $updates = exec_($cmd);
					my $updateCount = trim(exec_("$cmd | wc -l"));

					if ($updateCount && $updateCount > 0) {
						trace("Found $updateCount update(s).");
					} else {
						trace("No updates -- skip.");
						next;
					}
				}
			}

			trace("Pull...");
			exec_("git pull");

			trace("Add remote...");
			exec_('git remote add gitorious git@git.igk.intel.com:gilbert/gilbert.git');

			trace("Push to remote...");
			exec_("git push gitorious $_:$_ --force");
		}	
	}

	trace("");
}

process()
