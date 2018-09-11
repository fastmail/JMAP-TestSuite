use jmaptest;

# Can't have existing messages so must be pristine
attr pristine => 1;

test {
  my ($self) = @_;

  my $account = $self->pristine_account;

  my %mailboxes = (
    aaa => $account->create_mailbox({ name => "aaa" }),
    bbb => $account->create_mailbox({ name => "bbb" }),
    ccc => $account->create_mailbox({ name => "ccc" }),
    ddd => $account->create_mailbox({ name => "ddd" }),
  );

  my %in_aaa = (
    aaa_1      => $mailboxes{aaa}->add_message({ subject => 'aaa_1', }),
    aaa_old    => $mailboxes{aaa}->add_message({
      subject    => 'aaa_old',
      receivedAt => '2017-08-08T05:04:03Z',
      from       => 'fromtest@example.com',
      body       => 'a test body thing',
    }),
    aaa_future => $mailboxes{aaa}->add_message({
      subject    => 'aaa_future',
      receivedAt => '2040-08-08T05:04:03Z',
      body       => "the future is here",
      to         => 'totest@example.com',
    }),
    aaa_large  => $mailboxes{aaa}->add_message({
      subject    => 'aaa_large',
      body       => 'x' x (1000 * 500), # .5mb, roughly
      headers    => [
        cc => 'cctest@example.com',
        'x-foo' => 'bar',
      ],
    }),
    aaa_keyword_some => $mailboxes{aaa}->add_message({
      subject  => 'aaa_keyword_some',
      keywords => { some => jtrue() },
      headers    => [
        bcc => 'b.c.ctest@example.com',
        'x-foo' => 'baz',
        'x-bar' => 'bar',
      ],
    }),
    aaa_keyword_all => $mailboxes{aaa}->add_message({
      subject  => 'aaa_keyword_all',
      keywords => { all => jtrue() },
    }),
    aaa_with_attachment => $mailboxes{aaa}->add_message({
      subject    => 'aaa_with_attachment',
      email_type => 'with_attachment',
    }),
  );

  $in_aaa{aaa_keyword_some_reply_1} = $in_aaa{aaa_keyword_some}->reply({
    subject => 'aaa_keyword_some_reply_1',
  });

  $in_aaa{aaa_keyword_some_reply_2} = $in_aaa{aaa_keyword_some_reply_1}->reply({
    subject => 'aaa_keyword_some_reply_2',
    keywords => { some => jtrue() },
  });

  $in_aaa{aaa_keyword_all_reply_1} = $in_aaa{aaa_keyword_all}->reply({
    subject => 'aaa_keyword_all_reply_1',
    keywords => { all => jtrue() },
  });

  $in_aaa{aaa_keyword_all_reply_2} = $in_aaa{aaa_keyword_all_reply_1}->reply({
    subject => 'aaa_keyword_all_reply_2',
    keywords => { all => jtrue() },
  });

  my %in_bbb = (
    bbb_1 => $mailboxes{bbb}->add_message({ subject => 'bbb_1', }),
  );

  my %in_ccc = (
    ccc_1 => $mailboxes{ccc}->add_message({ subject => 'ccc_1', }),
  );

  my %in_ddd = (
    ddd_1 => $mailboxes{ddd}->add_message({ subject => 'ddd_1', }),
  );

  my %emails = (%in_aaa, %in_bbb, %in_ccc, %in_ddd);

  my %emails_by_id = map {; $_->id => $_ } values %emails;

  my $describer_sub = $self->make_describer_sub(\%emails_by_id);

  # inMailbox
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => { inMailbox => $mailboxes{aaa}->id },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    { ids => ids_for(%in_aaa), },
    $describer_sub,
    "inMailbox filter",
  );

  # inMailboxOtherThan
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => { inMailboxOtherThan => [ $mailboxes{aaa}->id ] },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    { ids => ids_for(%in_bbb, %in_ccc, %in_ddd), },
    $describer_sub,
    "inMailboxOtherThan filter excluded in_aaa",
  );

  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        inMailboxOtherThan => [ $mailboxes{aaa}->id, $mailboxes{bbb}->id ]
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    { ids => ids_for(%in_ccc, %in_ddd), },
    $describer_sub,
    "inMailboxOtherThan filter excluded in_aaa and in_bbb",
  );

  # before
  $self->test_query(
    $account,
     "Email/query",
    {
      filter => {
        before => '2017-10-10T05:05:05Z',
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    { ids => [ $emails{aaa_old}->id, ], },
    $describer_sub,
    "before filter",
  );

  # after
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        after => '2040-02-02T05:04:03Z',
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    { ids => [ $emails{aaa_future}->id, ], },
    $describer_sub,
    "after filter",
  );

  # minSize
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        minSize => 1000 * 450, # < .5mb
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    { ids => [ $emails{aaa_large}->id, ], },
    $describer_sub,
    "minSize filter",
  );

  # maxSize
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        maxSize => 1000 * 450, # < .5mb
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [
        grep {; $_ ne $emails{aaa_large}->id } @{ ids_for(%emails) },
      ],
    },
    $describer_sub,
    "maxSize filter",
  );

  # allInThreadHaveKeyword
  SKIP: {
    skip "No support for allInThreadHaveKeyword", 2
      if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

    $self->test_query(
      $account,
      "Email/query",
      {
        filter => {
          allInThreadHaveKeyword => 'some',
        },
        sort   => [{ property => 'subject', isAscending => jtrue()  }],
      },
      {
        ids => [], # Only some have this keyword
      },
      $describer_sub,
      "allInThreadHaveKeyword filter, none match that all have",
    );

    $self->test_query(
      $account,
      "Email/query",
      {
        filter => {
          allInThreadHaveKeyword => 'all',
        },
        sort   => [{ property => 'subject', isAscending => jtrue()  }],
      },
      {
        ids => ids_for(
          grep {; $_->subject =~ /^aaa_keyword_all/ } values %emails,
        ),
      },
      $describer_sub,
      "allInThreadHaveKeyword filter, one matches that all have",
    );
  }

  # someInThreadHaveKeyword
  SKIP: {
    skip "No support for someInThreadHaveKeyword", 2
      if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

    $self->test_query(
      $account,
      "Email/query",
      {
        filter => {
          someInThreadHaveKeyword => 'nope',
        },
        sort   => [{ property => 'subject', isAscending => jtrue()  }],
      },
      {
        ids => [],
      },
      $describer_sub,
      "someInThreadHaveKeyword filter, no match",
    );

    $self->test_query(
      $account,
      "Email/query",
      {
        filter => {
          someInThreadHaveKeyword => 'some',
        },
        sort   => [{ property => 'subject', isAscending => jtrue()  }],
      },
      {
        ids => ids_for(
          grep {; $_->subject =~ /^aaa_keyword_some/ } values %emails,
        ),
      },
      $describer_sub,
      "someInThreadHaveKeyword filter, match",
    );
  }

  # noneInThreadHaveKeyword
  SKIP: {
    skip "No support for noneInThreadHaveKeyword", 2
      if $self->server->isa('JMAP::TestSuite::ServerAdapter::Cyrus');

    $self->test_query(
      $account,
      "Email/query",
      {
        filter => {
          noneInThreadHaveKeyword => 'nope',
        },
        sort   => [{ property => 'subject', isAscending => jtrue()  }],
      },
      {
        ids => ids_for(%emails),
      },
      $describer_sub,
      "noneInThreadHaveKeyword filter, no match, get all back",
    );

    $self->test_query(
      $account,
      "Email/query",
      {
        filter => {
          noneInThreadHaveKeyword => 'some',
        },
        sort   => [{ property => 'subject', isAscending => jtrue()  }],
      },
      {
        ids => ids_for(
          grep {; $_->subject !~ /^aaa_keyword_some/ } values %emails,
        )
      },
      $describer_sub,
      "noneInThreadHaveKeyword filter, match, don't get some back",
    );
  }

  # hasKeyword
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        hasKeyword => 'some',
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [
	$emails{aaa_keyword_some}->id,
        $emails{aaa_keyword_some_reply_2}->id,
      ],
    },
    $describer_sub,
    "hasKeyword filter, match",
  );

  # notKeyword
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        notKeyword => 'some',
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => ids_for(
        grep {;
             $_->subject ne 'aaa_keyword_some'
          && $_->subject ne 'aaa_keyword_some_reply_2'
        } values %emails,
      ),
    },
    $describer_sub,
    "notKeyword filter, match",
  );

  # hasAttachment
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        hasAttachment => jfalse(),
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [
        grep {; $_ ne $emails{aaa_with_attachment}->id } @{ ids_for(%emails) },
      ],
    },
    $describer_sub,
    "hasAttachment false, matches all but 1",
  );

  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        hasAttachment => jtrue(),
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [ $emails{aaa_with_attachment}->id ],
    },
    $describer_sub,
    "hasAttachment true, matches only 1",
  );

  # text
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        text => "here",
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [ $emails{aaa_future}->id ],
   },
    $describer_sub,
    "text search",
  );

  # from
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        from => "fromtest",
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [ $emails{aaa_old}->id ],
    },
    $describer_sub,
    "from search",
  );

  # to
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        to => "totest",
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [ $emails{aaa_future}->id ],
    },
    $describer_sub,
    "to search",
  );

  # cc
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        cc => "cctest",
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [ $emails{aaa_large}->id ],
    },
    $describer_sub,
    "cc search",
  );

  # bcc
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        bcc => "b.c.ctest",
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [ $emails{aaa_keyword_some}->id ],
    },
    $describer_sub,
    "bcc search",
  );

  # subject
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        subject => "aaa_future",
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [ $emails{aaa_future}->id ],
    },
    $describer_sub,
    "subject search",
  );

  # body
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        body => "test body thing",
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [ $emails{aaa_old}->id ],
    },
    $describer_sub,
    "body search",
  );

  # header, form one (match if header exists)
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        header => [ 'x-foo' ],
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [ $emails{aaa_keyword_some}->id, $emails{aaa_large}->id ],
    },
    $describer_sub,
    "header exists search",
  );

  # header, form two (match if header/value match)
  $self->test_query(
    $account,
    "Email/query",
    {
      filter => {
        header => [ 'x-foo', 'bar' ],
      },
      sort   => [{ property => 'subject', isAscending => jtrue()  }],
    },
    {
      ids => [ $emails{aaa_large}->id ],
    },
    $describer_sub,
    "header exists and matches search",
  );
};

# Allows ids_for(%hash) and ids_for(@list)
sub ids_for {
  my @list = @_;

  return [
    map  {; $_->id }
    sort { $a->subject cmp $b->subject }
    grep {; ref($_) }
    values @list,
  ];
}

sub make_describer_sub {
  my ($self, $emails_by_id) = @_;

  return sub {
    my ($self, $id) = @_;

    return    $emails_by_id->{$id}->{subject}
           || $emails_by_id->{$id}->subject;
  }
}
