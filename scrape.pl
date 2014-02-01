use utf8;
use Mojo::UserAgent;
use Data::Dumper;
use Encode qw(decode encode);
use DBI;
use Data::Dumper;
use List::MoreUtils qw(uniq);
use Encode qw(decode encode);

sub get_stage_results {
	my $tx = shift;

	my @list = ();

	my $last_time;
	my $first_time;

	$tx->res->dom('table#list9 tbody tr')->each(sub {
		my $tr = shift;

		my $pos = $tr->td->[0]->text;

		# Treat more different statuses here, like DNS

		$pos += 0;

		my $rider_slug;
		my $team_slug;
		($rider_slug) = $tr->td->[1]->find('a')->first->{'href'} =~ /rider\/(.+)/;
		eval {
			($team_slug)  = $tr->td->[2]->find('a')->first->{'href'} =~ /team\/(.+)/;
		};
		if ($@) {
			$team_slug = "";
		}

		my $time = $tr->td->[5]->text;

		if ($time eq ',,') {
			$time = $last_time;
		}
		$last_time = $time;
		$time .= '.000';

		push @list, {
			pos        => $pos,
			rider_slug => $rider_slug,
			team_slug  => $team_slug,
			time       => $time,
		};
	});

	my $LOGFILE;

	open $LOGFILE, '>>', "list.log";
	print { $LOGFILE } "\n\n-------------------------------------------";
	print { $LOGFILE } Dumper(@list);
	close $LOGFILE;

	return @list;
}

sub import_race {
	my $dbh = shift;
	my $url = shift;

	my $ua = Mojo::UserAgent->new;
	my $tx = $ua->get($url);

	# Create race
	my ($race_slug) = $tx->res->dom->find('ul#tabmenu2 li a')->first->{'href'} =~ /race\/(.*)/;
	print "Race slug: $race_slug\n";

	$dbh->do("
		INSERT INTO
		  race (procyclingstats_slug)
		VALUES (?)
		", undef, $race_slug);

	my ($race) = $dbh->selectrow_array("
		SELECT
		  race
		FROM
		  race
		WHERE
		  procyclingstats_slug = ?
		", undef, $race_slug);

	print "Race ID: $race\n";

	$tx->res->dom('table#list5 tbody tr')->each(sub {
		my $tr = shift;

		my ($stage_url) = $tr->td->[2]->a->{'href'};
		print "Found stage: $stage_url\n";
		$stage_url = "http://www.procyclingstats.com/" . $stage_url; # FIXME

		# Does this work?
		if ($stage_url =~ /lassification/) {
			return;
		}

		import_stage($dbh, $race, $stage_url);
		sleep 3;
	});
}

sub import_stage {
	my $dbh  = shift;
	my $url  = shift;
	my $race = shift;

	my $ua = Mojo::UserAgent->new;
	my $tx = $ua->get($url);

	my @list = get_stage_results($tx);

	my $type = $tx->res->dom->find('div.content div h2 font.blue')->first->text =~ /ITT/ ? 'ITT'
		 : $tx->res->dom->find('div.content div h2 font.blue')->first->text =~ /TTT/ ? 'TTT'
		 : $tx->res->dom->find('div.content div h2 font.blue')->first->text =~ 'Prologue' ? 'Prologue'
		 : 'NORMAL';

	print "Stage type: $type\n";

	my $prologue;
	if ($type eq 'Prologue') {
		$prologue = 1;
		$type     = 'ITT';
	}

	my $name = $tx->res->dom->find('div.content div h2 font.red')->first->text;
	my ($slug) = $tx->res->dom->find('ul#tabmenu2 li a.cur')->first->attrs('href') =~ /race\/(.*)/;
	my ($dd, $mm, $yyyy) = $tx->res->dom->all_text =~ /Date:.*?(\d+)\.(\d+)\.(\d+)/;

	print "Date: $yyyy-$mm-$dd\n";
	print "Name: $name\n";
	print "Slug: $slug\n";

	# FIXME: Just do a cascading delete on the whole stage
	my $stage_exists = 0;
	$dbh->do("
		INSERT INTO
		  stage (race, \"type\", date, name, prologue, procyclingstats_slug)
		VALUES (?, ?, ?, ?, ?, ?)
		", undef, $race, $type, "$yyyy-$mm-$dd", $name, $prologue, $slug)
		or do { $stage_exists = 1; };

	my ($stage) = $dbh->selectrow_array("
		SELECT
		  stage
		FROM
		  stage 
		WHERE
		  procyclingstats_slug = ?
		", undef, $slug);

	my $finish_exists = 0;
	$dbh->do("
		INSERT INTO
		  line (stage, \"type\", name)
		VALUES (?, ?, ?)
		", undef, $stage, 'FINISH', 'Finish') or do { $finish_exists = 1; };

	my ($line) = $dbh->selectrow_array("
		SELECT
		  line
		FROM
		  line
		WHERE
		  stage = ?
		AND
		  \"type\" = 'FINISH'
		", undef, $stage);

	$dbh->do("
		DELETE FROM
		  rider_line
		WHERE
		  line = ?
		", undef, $line);

	my $tsth = $dbh->prepare("
		INSERT INTO
		  team (procyclingstats_slug)
		VALUES (?)
		");

	my @team_slugs = uniq(map { $_->{'team_slug'} eq '' ? () : $_->{'team_slug'} } @list);
	my @new_teams = ();
	for my $team_slug (@team_slugs) {
		if ($tsth->execute($team_slug)) {
			push @new_teams, $team_slug;
			print "Added new team: $team_slug\n";
		}
	}

	my $rsth = $dbh->prepare("
		INSERT INTO
		  rider (procyclingstats_slug)
		VALUES (?)
		");

	my $rlsth = $dbh->prepare("
		INSERT INTO
		  rider_line (rider, line, \"number\", time)
		SELECT rider, ?, ?, ?::INTERVAL + ?::INTERVAL
		FROM
		  rider
		WHERE
		  rider.procyclingstats_slug = ?
		");

	my $rrsth = $dbh->prepare("
		INSERT INTO
		  rider_race (rider, race, team)
		SELECT rider, ?, team
		FROM
		  rider, team
		WHERE
		  rider.procyclingstats_slug = ?
		AND
		  team.procyclingstats_slug = ?
		");

	my @new_riders = ();
	for my $rider (@list) {
		if ($rsth->execute($rider->{'rider_slug'})) {
			push @new_riders, $rider->{'rider_slug'};
			print "Added new rider: $rider->{'rider_slug'}\n";
		}

		if ($rrsth->execute($race, $rider->{'rider_slug'}, $rider->{'team_slug'})) {
			print "New race ($race) participant: $rider->{'rider_slug'} ";
			print "on $rider->{'team_slug'}\n";
		}

		# FIXME: Check DNF etc.
		$rlsth->execute(
			$line,
			$rider->{'pos'},
			$rider->{'time'} eq $list[0]->{'time'} ? 0 : $list[0]->{'time'},
			$rider->{'time'},
			$rider->{'rider_slug'}
		);
	}

	return @new_riders;
}

binmode STDOUT, ":utf8";

my $url  = $ARGV[0];
my $race = $ARGV[1];

my $dbh = DBI->connect("dbi:Pg:database=lebase",
	"lebase",
	"l4ll3b4s3",
	{
		pg_enable_utf8 => 1,
		RaiseError => 0,
		PrintError => 0,
	}
);

import_stage($dbh, $url, $race);

