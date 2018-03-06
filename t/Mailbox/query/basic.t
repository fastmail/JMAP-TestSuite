use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok pristine_test);

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;
use JSON qw(decode_json);
use JSON::Typist;

# XXX - Need test for cancalc

pristine_test "Mailbox/query with no existing entities" => sub {
  my ($self) = @_;

  plan skip_all => "Cyrus requires at least one mailbox"
    if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  my $tester = $self->tester;

  subtest "No arguments" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/query" => {},
      ]],
    });
    ok($res->is_success, "Mailbox/query")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/query")->arguments,
      superhashof({
        accountId => jstr($self->context->accountId),
        state     => jstr(),
        position  => jnum(0),
        total     => jnum(0),
        ids       => [],
        canCalculateChanges => jbool(),
      }),
      "No mailboxes looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};

# XXX - Test for basic response

pristine_test "Mailbox/query filtering with filterConditions" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mailbox1 = $self->context->create_mailbox;

  my $mailbox2 = $self->context->create_mailbox({
    parentId => $mailbox1->id,
  });

  subtest "parentId" => sub {

    subtest "does not have a parentId" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/query" => {
            filter => {
              parentId => undef,
            },
          },
        ]],
      });
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, supersetof($mailbox1->id), 'Got top-level mailbox');
      jcmp_deeply($ids, noneof($mailbox2->id), 'Did not get sub-mailbox');
    };

    subtest "has a parentId" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/query" => {
            filter => {
              parentId => $mailbox1->id,
            },
          },
        ]],
      });
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, [ $mailbox2->id ], 'Got our one child mailbox');
    };
  };

  subtest "hasRole" => sub {
    # Find some mailboxes with roles
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/get" => {},
      ]],
    });

    my @with_roles = map {;
      $_->{id}
    } grep {;
      $_->{role}
    } @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

    plan skip_all => "No mailboxes with roles found, can't continue"
      unless @with_roles;

    subtest "false" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/query" => {
            filter => {
              hasRole => JSON::false,
            },
          },
        ]],
      });
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply(
        $ids,
        supersetof($mailbox1->id, $mailbox2->id),
        'Got mailboxes with no roles',
      );

      jcmp_deeply(
        $ids,
        noneof(@with_roles),
        'Did not get mailboxes with roles',
      ) or diag explain $ids;
    };

    subtest "true" => sub {
      my $res = $tester->request({
        using => [ "ietf:jmapmail" ],
        methodCalls => [[
          "Mailbox/query" => {
            filter => {
              hasRole => JSON::true,
            },
          },
        ]],
      });
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, \@with_roles, 'Got mailboxes with roles only');
    };
  };
};

pristine_test "sorting" => sub {
  my ($self) = @_;

  my %mailboxes = (
    zzz => $self->context->create_mailbox({
      name => "zzz", sortOrder => 1,
    }),
    xxx => $self->context->create_mailbox({
      name => "xxx", sortOrder => 2,
    }),
    yyy => $self->context->create_mailbox({
      name => "yyy", sortOrder => 3,
    }),
  );

  $mailboxes{bbb} = $self->context->create_mailbox({
    name => 'bbb', sortOrder => 4, parentId => $mailboxes{zzz}->id,
  });
  $mailboxes{aaa} = $self->context->create_mailbox({
    name => 'aaa', sortOrder => 5, parentId => $mailboxes{zzz}->id,
  });

  $mailboxes{ccc} = $self->context->create_mailbox({
    name => 'ccc', sortOrder => 6, parentId => $mailboxes{xxx}->id,
  });

  $mailboxes{ddd} = $self->context->create_mailbox({
    name => 'ddd', sortOrder => 7, parentId => $mailboxes{yyy}->id,
  });

  my %mailboxes_by_id = map {; $_->id => $_ } values %mailboxes;

  my @name_asc = map {; $_->id } @mailboxes{qw(
    aaa bbb ccc ddd xxx yyy zzz
  )};
  my @name_desc = reverse @name_asc;

  my @sort_order_asc = map {; $_->id } @mailboxes{qw(
    zzz xxx yyy bbb aaa ccc ddd
  )};
  my @sort_order_desc = reverse @sort_order_asc;

  my @parent_name_asc = map {; $_->id } @mailboxes{qw(
    xxx
      ccc
    yyy
      ddd
    zzz
      aaa
      bbb
  )};
  my @parent_name_desc = reverse @parent_name_asc;

  # name
  $self->test_sort(
    { sort => [{ property => 'name', }], },
    { ids => \@name_asc, },
    \%mailboxes_by_id,
    "sort by name, implicit ascending order (default)",
  );

  $self->test_sort(
    { sort => [{ property => 'name', isAscending => JSON::true, }], },
    { ids => \@name_asc, },
    \%mailboxes_by_id,
    "sort by name, explicit ascending order",
  );

  $self->test_sort(
    { sort => [{ property => 'name', isAscending => JSON::false, }], },
    { ids => \@name_desc, },
    \%mailboxes_by_id,
    "sort by name, explicit descending order",
  );

  # sortOrder
  $self->test_sort(
    { sort => [{ property => 'sortOrder', }], },
    { ids => \@sort_order_asc, },
    \%mailboxes_by_id,
    "sort by sortOrder, implict ascending order"
  );

  $self->test_sort(
    { sort => [{ property => 'sortOrder', isAscending => JSON::true, }], },
    { ids => \@sort_order_asc, },
    \%mailboxes_by_id,
    "sort by sortOrder, explicit ascending order"
  );

  $self->test_sort(
    { sort => [{ property => 'sortOrder', isAscending => JSON::false, }], },
    { ids => \@sort_order_desc, },
    \%mailboxes_by_id,
    "sort by sortOrder, explicit descending order"
  );

  # parent/name
  $self->test_sort(
    { sort => [{ property => 'parent/name', }], },
    { ids => \@parent_name_asc, },
    \%mailboxes_by_id,
    "sort by parent/name, implict ascending order"
  );

  $self->test_sort(
    { sort => [{ property => 'parent/name', isAscending => JSON::true, }], },
    { ids => \@parent_name_asc, },
    \%mailboxes_by_id,
    "sort by parent/name, explicit ascending order"
  );

  $self->test_sort(
    { sort => [{ property => 'parent/name', isAscending => JSON::false, }], },
    { ids => \@parent_name_desc, },
    \%mailboxes_by_id,
    "sort by parent/name, explicit descending order"
  );

  # position 0, explicit
  $self->test_sort(
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => 0,
    },
    { ids => \@parent_name_asc, },
    \%mailboxes_by_id,
    "sort by parent/name, explicit ascending order, explicit position 0"
  );

  # negative positions start at end of list
  $self->test_sort(
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => -1,
    },
    { ids => [ $parent_name_asc[-1] ], position => $#parent_name_asc, },
    \%mailboxes_by_id,
    "sort by parent/name, explicit ascending order, explicit position -1"
  );

  $self->test_sort(
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => -3,
    },
    { ids => [ @parent_name_asc[-3..-1] ], position => $#parent_name_asc - 2, },
    \%mailboxes_by_id,
    "sort by parent/name, explicit ascending order, explicit position -3"
  );

  # positive positions start at beginning
  $self->test_sort(
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => 1,
    },
    { ids => [ @parent_name_asc[1..$#parent_name_asc] ], position => 1, },
    \%mailboxes_by_id,
    "sort by parent/name, explicit ascending order, explicit position 1"
  );

  $self->test_sort(
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => 3,
    },
    { ids => [ @parent_name_asc[3..$#parent_name_asc] ], position => 3, },
    \%mailboxes_by_id,
    "sort by parent/name, explicit ascending order, explicit position 3"
  );

  # position > total = no results
  $self->test_sort(
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => $#parent_name_asc + 5,
    },
    { ids => [], position => $#parent_name_asc + 5, },
    \%mailboxes_by_id,
    "sort by parent/name, explicit ascending order, explicit position too high"
  );

  # negative position too low clamped to 0
  $self->test_sort(
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => $#parent_name_asc - ($#parent_name_asc + 10),
    },
    { ids => \@parent_name_asc, position => 0, },
    \%mailboxes_by_id,
    "sort by parent/name, explicit ascending order, explicit position too low"
  );

};

sub test_sort {
  my ($self, $args, $expect, $mailboxes_by_id, $test) = @_;

  my $tester = $self->tester;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  $args->{filter}{hasRole} = JSON::false;

  subtest "$test" => sub {
    my $res = $tester->request({
      using => [ "ietf:jmapmail" ],
      methodCalls => [[
        "Mailbox/query" => $args,
      ]],
    });
    ok($res->is_success, "Mailbox/query")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/query")->arguments,
      superhashof({
        accountId => jstr($self->context->accountId),
        state     => jstr(),
        total     => jnum,
        position  => jnum(0),
        canCalculateChanges => jbool(),
        %$expect, # can override position
      }),
      "sorted as expected",
    ) or $self->explain_sort_failure($res, $expect->{ids}, $mailboxes_by_id);
  };
}

sub explain_sort_failure {
  my ($self, $res, $expect, $mailboxes_by_id) = @_;

  my $got = $res->single_sentence("Mailbox/query")->arguments->{ids};

  my @got_names = map {; $mailboxes_by_id->{$_}->name } @$got;
  my @exp_names = map {; $mailboxes_by_id->{$_}->name } @$expect;

  note("Got:    @got_names");
  note("Wanted: @exp_names");
}

run_me;
done_testing;
