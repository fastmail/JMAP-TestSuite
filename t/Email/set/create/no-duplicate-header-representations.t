use jmaptest;

use Data::GUID qw(guid_string);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  my $mbox = $account->create_mailbox;
  my $msg = $mbox->add_message;

  # parsed forms
  my %valid = (
    messageId  => sub { [ guid_string() . '@example.net' ] },
    inReplyTo  => sub { [ guid_string() . '@example.net' ] },
    references => sub { [ guid_string() . '@example.net' ] },
    sender     => sub { [ { email => 'sender@example.org' } ] },
    from       => sub { [ { email => 'from@example.org' } ] },
    to         => sub { [ { email => 'to@example.org' } ] },
    cc         => sub { [ { email => 'cc@example.org' } ] },
    bcc        => sub { [ { email => 'bcc@example.org' } ] },
    replyTo    => sub { [ { email => 'replyTo@example.org' } ] },
    subject    => sub { 'a subject' },
    sentAt     => sub { '2018-08-30T12:00:59-04:00' },
  );

  my %map = (
    messageId => 'Message-Id',
    inReplyTo => 'In-Reply-To',
    replyTo   => 'Reply-To',
    sentAt    => 'Date',
  );

  my %valid_raw = (
    'Message-Id'  => sub { '<' . guid_string() . '@example.net' . '>' },
    'In-Reply-To' => sub { '<' . guid_string() . '@example.net' . '>' },
    references    => sub { '<' . guid_string() . '@example.net' . '>' },
    sender        => sub { 'sender@example.org' },
    from          => sub { 'from@example.org' },
    to            => sub { 'to@example.org' },
    cc            => sub { 'cc@example.org' },
    bcc           => sub { 'bcc@example.org' },
    'Reply-To'    => sub { 'replyTo@example.org' },
    subject       => sub { 'a subject' },
    Date          => sub { '2018-08-30T12:00:59-04:00' },
  );

  subtest "sanity check" => sub {
    for my $hdr (sort keys %valid) {
      $tester->request_ok(
        [
          "Email/set" => {
            create => {
              new => {
                mailboxIds => { $mbox->id => \1, },
                $hdr       => $valid{$hdr}->(),
              },
            },
          },
        ],
        superhashof({
          created => {
            new => superhashof({ id => jstr }),
          },
        }),
        "Created a message with a $hdr header"
      );
    }

    for my $hdr (sort keys %valid_raw) {
      $tester->request_ok(
        [
          "Email/set" => {
            create => {
              new => {
                mailboxIds    => { $mbox->id => \1, },
                "header:$hdr" => $valid_raw{$hdr}->(),
              },
            },
          },
        ],
        superhashof({
          created => {
            new => superhashof({ id => jstr }),
          },
        }),
        "Created a message with a header:$hdr header"
      );
    }
  };

  subtest "duplicates not allowed" => sub {
    for my $hdr (sort keys %valid) {
      my $raw = $map{$hdr} || $hdr;

      $tester->request_ok(
        [
          "Email/set" => {
            create => {
              new => {
                mailboxIds    => { $mbox->id => \1, },
                $hdr          => $valid{$hdr}->(),
                "header:$raw" => $valid_raw{$raw}->(),
              },
            },
          },
        ],
        superhashof({
          notCreated => {
            new => {
              type => 'invalidProperties',
              properties => any([$hdr], ["header:$raw"]), # either is fine
            },
          },
        }),
        "Could not provide $hdr and header:$raw"
      );
    }
  };
};
