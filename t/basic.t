use strict;
use warnings;

use JMAP::TestSuite::Instance;

use Test::Deep::JType;
use Test::More;

my $ti = JMAP::TestSuite::Instance->new({
  jmap_uri    => q{http://localhost:9000/jmap/b0b7699c-4474-11e6-b790-f23c91556942},
  upload_uri  => q{http://localhost:9000/upload/b0b7699c-4474-11e6-b790-f23c91556942},
});

$ti->simple_test(sub {
  my ($tester) = @_;
  my $res = $tester->request([[ getMailboxes => {} ]]);

  my $pairs = $res->as_pairs;

  is(@$pairs, 1, "one sentence of response to getMailboxes");

  my @mailboxes = @{ $pairs->[0][1]{list} };

  my %role;
  for my $mailbox (grep {; defined $_->{role} } @mailboxes) {
    if ($role{ $mailbox->{role} }) {
      fail("role $mailbox->{role} appears multiple times");
    }

    note("found mailbox for $mailbox->{role}");
    $role{ $mailbox->{role} } = $mailbox;
  }
});

done_testing;
