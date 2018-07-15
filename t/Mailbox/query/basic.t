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
use Test::Abortable;

# XXX - Need test for cancalc

# This is about testing when there's no mailboxes, so you need a brand new
# account, basically.
pristine_test "Mailbox/query with no existing entities" => sub {
  my ($self) = @_;

  plan skip_all => "Cyrus requires at least one mailbox"
    if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

  my $tester = $self->tester;

  subtest "No arguments" => sub {
    my $res = $tester->request([[
      "Mailbox/query" => {},
    ]]);
    ok($res->is_success, "Mailbox/query")
      or diag explain $res->http_response->as_string;

    jcmp_deeply(
      $res->single_sentence("Mailbox/query")->arguments,
      superhashof({
        accountId  => jstr($self->context->accountId),
        queryState => jstr(),
        position   => jnum(0),
        total      => jnum(0),
        ids        => [],
        canCalculateChanges => jbool(),
      }),
      "No mailboxes looks good",
    ) or diag explain $res->as_stripped_triples;
  };
};

# XXX - Test for basic response

# We need to know that only our mailboxes here exist for predicting filter
# results, so we need a pristine account.
pristine_test "Mailbox/query filtering with filterConditions" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mailbox1 = $self->context->create_mailbox;

  my $mailbox2 = $self->context->create_mailbox({
    parentId => $mailbox1->id,
  });

  subtest "parentId" => sub {

    subtest "does not have a parentId" => sub {
      my $res = $tester->request([[
        "Mailbox/query" => {
          filter => {
            parentId => undef,
          },
        },
      ]]);
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, supersetof($mailbox1->id), 'Got top-level mailbox');
      jcmp_deeply($ids, noneof($mailbox2->id), 'Did not get sub-mailbox');
    };

    subtest "has a parentId" => sub {
      my $res = $tester->request([[
        "Mailbox/query" => {
          filter => {
            parentId => $mailbox1->id,
          },
        },
      ]]);
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, [ $mailbox2->id ], 'Got our one child mailbox');
    };
  };

  subtest "hasRole" => sub {
    # Find some mailboxes with roles
    my $res = $tester->request([[
      "Mailbox/get" => {},
    ]]);

    my @with_roles = map {;
      $_->{id}
    } grep {;
      $_->{role}
    } @{ $res->single_sentence("Mailbox/get")->arguments->{list} };

    plan skip_all => "No mailboxes with roles found, can't continue"
      unless @with_roles;

    subtest "false" => sub {
      my $res = $tester->request([[
        "Mailbox/query" => {
          filter => {
            hasRole => JSON::false,
          },
        },
      ]]);
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
      my $res = $tester->request([[
        "Mailbox/query" => {
          filter => {
            hasRole => JSON::true,
          },
        },
      ]]);
      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      my $ids = $res->single_sentence("Mailbox/query")->arguments->{ids};

      jcmp_deeply($ids, \@with_roles, 'Got mailboxes with roles only');
    };
  };
};

# We need to know that only our mailboxes here exist for predicting filter
# results, so we need a pristine account.
pristine_test "sorting and limiting" => sub {
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

  my $describer_sub = $self->make_describer_sub(\%mailboxes_by_id);

  # name
  $self->test_query("Mailbox/query",
    { sort => [{ property => 'name', }], },
    { ids => \@name_asc, },
    $describer_sub,
    "sort by name, implicit ascending order (default)",
  );

  $self->test_query("Mailbox/query",
    { sort => [{ property => 'name', isAscending => JSON::true, }], },
    { ids => \@name_asc, },
    $describer_sub,
    "sort by name, explicit ascending order",
  );

  $self->test_query("Mailbox/query",
    { sort => [{ property => 'name', isAscending => JSON::false, }], },
    { ids => \@name_desc, },
    $describer_sub,
    "sort by name, explicit descending order",
  );

  # sortOrder
  $self->test_query("Mailbox/query",
    { sort => [{ property => 'sortOrder', }], },
    { ids => \@sort_order_asc, },
    $describer_sub,
    "sort by sortOrder, implict ascending order"
  );

  $self->test_query("Mailbox/query",
    { sort => [{ property => 'sortOrder', isAscending => JSON::true, }], },
    { ids => \@sort_order_asc, },
    $describer_sub,
    "sort by sortOrder, explicit ascending order"
  );

  $self->test_query("Mailbox/query",
    { sort => [{ property => 'sortOrder', isAscending => JSON::false, }], },
    { ids => \@sort_order_desc, },
    $describer_sub,
    "sort by sortOrder, explicit descending order"
  );

  # parent/name
  $self->test_query("Mailbox/query",
    { sort => [{ property => 'parent/name', }], },
    { ids => \@parent_name_asc, },
    $describer_sub,
    "sort by parent/name, implict ascending order"
  );

  $self->test_query("Mailbox/query",
    { sort => [{ property => 'parent/name', isAscending => JSON::true, }], },
    { ids => \@parent_name_asc, },
    $describer_sub,
    "sort by parent/name, explicit ascending order"
  );

  $self->test_query("Mailbox/query",
    { sort => [{ property => 'parent/name', isAscending => JSON::false, }], },
    { ids => \@parent_name_desc, },
    $describer_sub,
    "sort by parent/name, explicit descending order"
  );

  # position 0, explicit
  $self->test_query("Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => 0,
    },
    { ids => \@parent_name_asc, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position 0"
  );

  # negative positions start at end of list
  $self->test_query("Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => -1,
    },
    { ids => [ $parent_name_asc[-1] ], position => $#parent_name_asc, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position -1"
  );

  $self->test_query("Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => -3,
    },
    { ids => [ @parent_name_asc[-3..-1] ], position => $#parent_name_asc - 2, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position -3"
  );

  # positive positions start at beginning
  $self->test_query("Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => 1,
    },
    { ids => [ @parent_name_asc[1..$#parent_name_asc] ], position => 1, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position 1"
  );

  $self->test_query("Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => 3,
    },
    { ids => [ @parent_name_asc[3..$#parent_name_asc] ], position => 3, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position 3"
  );

  # position > total = no results
  $self->test_query("Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => $#parent_name_asc + 5,
    },
    { ids => [], position => $#parent_name_asc + 5, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position too high"
  );

  # negative position too low clamped to 0
  $self->test_query("Mailbox/query",
    {
      sort => [{ property => 'parent/name', isAscending => JSON::true, }],
      position => $#parent_name_asc - ($#parent_name_asc + 10),
    },
    { ids => \@parent_name_asc, position => 0, },
    $describer_sub,
    "sort by parent/name, explicit ascending order, explicit position too low"
  );

  subtest "limits" => sub {
    subtest "Negative limit" => sub {
      my $res = $self->tester->request([[
        "Mailbox/query" => { limit => -5 },
      ]]);

      ok($res->is_success, "Mailbox/query")
        or diag explain $res->http_response->as_string;

      jcmp_deeply(
        $res->sentence(0)->arguments,
        superhashof({
          type => 'invalidArguments',
          arguments => [ 'limit' ],
        }),
        "got invalidArguments for negative limit",
      ) or diag explain $res->as_stripped_triples;
    };

    $self->test_query("Mailbox/query",
      {
        sort  => [{ property => 'parent/name', isAscending => JSON::true, }],
        limit => @parent_name_asc + 5,
      },
      { ids => \@parent_name_asc, total => 0+@parent_name_asc, },
      $describer_sub,
      "limit > total returns total"
    );

    $self->test_query("Mailbox/query",
      {
        sort  => [{ property => 'parent/name', isAscending => JSON::true, }],
        limit => 0 + @parent_name_asc,
      },
      { ids => \@parent_name_asc, total => 0+@parent_name_asc, },
      $describer_sub,
      "limit == total returns total"
    );

    $self->test_query("Mailbox/query",
      {
        sort  => [{ property => 'parent/name', isAscending => JSON::true, }],
        limit => @parent_name_asc - 2,
      },
      {
        ids => [ @parent_name_asc[0..($#parent_name_asc - 2)] ],
        total => 0+@parent_name_asc,
      },
      $describer_sub,
      "limit < total returns limit"
    );

    $self->test_query("Mailbox/query",
      {
        sort  => [{ property => 'parent/name', isAscending => JSON::true, }],
        limit => 0,
      },
      {
        ids => [ ],
        total => 0+@parent_name_asc,
      },
      $describer_sub,
      "limit 0 returns none"
    );
  };
};

# We need to know that only our mailboxes here exist for predicting filter
# results, so we need a pristine account.
pristine_test "Mailbox/query filtering with filterOperators" => sub {
  my ($self) = @_;

  my $tester = $self->tester;

  my $mailbox1 = $self->context->create_mailbox({
    name => 'aaa',
  });

  my $mailbox2 = $self->context->create_mailbox({
    parentId => $mailbox1->id,
    name => 'bbb',
  });

  my $res = $tester->request({
    using => [ "ietf:jmapmail" ],
    methodCalls => [[
      "Mailbox/get" => {},
    ]],
  });

  my @mailboxes = @{
    $res->single_sentence("Mailbox/get")->arguments->{list}
  };

  my @with_roles = grep {; $_->{role} } @mailboxes;

  plan skip_all => "No mailboxes with roles found, can't continue"
    unless @with_roles;

  my %mailboxes_by_id = map {; $_->{id} => $_ } @mailboxes;

  my $describer_sub = $self->make_describer_sub(\%mailboxes_by_id);

  my @all_name_asc = map {;
    $_->{id}
  } sort {
    $a->{name} cmp $b->{name}
  } @mailboxes;

  my @with_role_name_asc = map {;
    $_->{id}
  } sort {
    $a->{name} cmp $b->{name}
  } @with_roles;

  # AND
  $self->test_query("Mailbox/query",
    {
      filter => {
        operator => 'AND',
        conditions => [
          { hasRole => JSON::false, },
          { parentId => undef, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ $mailbox1->id ], },
    $describer_sub,
    "AND - two conditions",
  );

  $self->test_query("Mailbox/query",
    {
      filter => {
        operator => 'AND',
        conditions => [
          { hasRole => JSON::false, },
          { parentId => $mailbox1->id, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ $mailbox2->id ], },
    $describer_sub,
    "AND - two conditions",
  );

  $self->test_query("Mailbox/query",
    {
      filter => {
        operator => 'AND',
        conditions => [
          {
            operator => 'AND',
            conditions => [
              { hasRole => JSON::false, },
              { parentId => $mailbox1->id, },
            ],
          },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ $mailbox2->id ], },
    $describer_sub,
    "AND - two conditions nested one level deep",
  );

  # OR
  $self->test_query("Mailbox/query",
    {
      filter => {
        operator => 'OR',
        conditions => [
          { hasRole => JSON::false, },
          { parentId => $mailbox1->id, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ $mailbox1->id, $mailbox2->id ], },
    $describer_sub,
    "OR - two conditions",
  );

  $self->test_query("Mailbox/query",
    {
      filter => {
        operator => 'OR',
        conditions => [
          { hasRole => JSON::true, },
          { hasRole => JSON::true, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ @with_role_name_asc ], },
    $describer_sub,
    "OR - two conditions, same cond",
  );

  $self->test_query("Mailbox/query",
    {
      filter => {
        operator => 'OR',
        conditions => [
          { hasRole => JSON::true, },
          { hasRole => JSON::false, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ @all_name_asc ], },
    $describer_sub,
    "OR - two conditions, diff conds",
  );

  # NOT
  $self->test_query("Mailbox/query",
    {
      filter => {
        operator => 'NOT',
        conditions => [
          { hasRole => JSON::true, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ $mailbox1->id, $mailbox2->id ], },
    $describer_sub,
    "NOT - one condition",
  );

  $self->test_query("Mailbox/query",
    {
      filter => {
        operator => 'NOT',
        conditions => [
          { hasRole => JSON::true, },
          { hasRole => JSON::false, },
        ],
      },
      sort => [{ property => 'name', isAscending => JSON::true, }],
    },
    { ids => [ ], },
    $describer_sub,
    "NOT - two conditions",
  );
};

sub make_describer_sub {
  my ($self, $mailboxes_by_id) = @_;

  return sub {
    my ($self, $id) = @_;

    return    $mailboxes_by_id->{$id}->{name}
           || $mailboxes_by_id->{$id}->name;
  }
}


run_me;
done_testing;
