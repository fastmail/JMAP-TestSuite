use jmaptest;
use JMAP::TestSuite::Util qw(email_create_invalid_or_repaired);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox = $account->create_mailbox;

  # RFC 8621 S4.6: charset "MUST be omitted if a partId is given", because the
  # server chooses the encoding of the value.
  email_create_invalid_or_repaired(
    $tester,
    {
      mailboxIds => { $mbox->id => jtrue },
      bodyStructure => {
        partId  => 'text',
        type    => 'text/plain',
        charset => 'us-ascii',
      },
      bodyValues => {
        text => {
          value => 'ok',
        }
      },
    },
    { properties => [ 'textBody', 'bodyValues' ], fetchTextBodyValues => jtrue },
    sub {
      my ($email) = @_;
      my $part_id = $email->{textBody}[0]{partId};
      is($email->{bodyValues}{$part_id // ''}{value}, 'ok', "the body value survives");
    },
    "charset with partId",
  );
};
