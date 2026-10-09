use jmaptest;

# draft-ietf-jmap-calendars S3.1: a standard /get; "The ids argument may be
# null to fetch all at once."

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:calendars',
  );

  my $res = $tester->request([[
    "ParticipantIdentity/get" => { ids => undef },
  ]]);
  ok($res->is_success, 'ParticipantIdentity/get') or diag explain $res->response_payload;

  # RFC 8620 S5.1 response arguments.
  my $args = $res->single_sentence("ParticipantIdentity/get")->arguments;
  jcmp_deeply(
    $args,
    {
      accountId => jstr($account->accountId),
      state     => jstr,
      list      => ignore(),
      notFound  => [],
    },
    'response has the standard /get arguments',
  ) or diag explain $res->as_stripped_triples;

  my $list = $args->{list} // [];
  for my $pi (@$list) {
    # S3: name has a default, isDefault is server-set; all are returned.
    jcmp_deeply(
      $pi,
      superhashof({
        id              => jstr,
        name            => jstr,
        calendarAddress => jstr,
        isDefault       => jbool,
      }),
      'identity has id, name, calendarAddress and isDefault',
    ) or diag explain $pi;
  }

  # S3: isDefault "MUST NOT be true for more than one participant identity".
  ok((grep { $_->{isDefault} } @$list) <= 1, 'at most one default identity')
    or diag explain $list;

  my $nres = $tester->request([[
    "ParticipantIdentity/get" => { ids => [ 'no-such-identity' ] },
  ]]);
  jcmp_deeply(
    $nres->single_sentence("ParticipantIdentity/get")->arguments,
    superhashof({ list => [], notFound => [ 'no-such-identity' ] }),
    'unknown id is in notFound',
  ) or diag explain $nres->as_stripped_triples;
};
