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

  # RFC 8621 S4.6: a partId "MUST" be present in bodyValues.
  email_create_invalid_or_repaired(
    $tester,
    {
      mailboxIds => { $mbox->id => jtrue },
      bodyStructure => {
        partId => 'text',
        type   => 'text/plain',
      },
      bodyValues => {
        notText => {
          value => 'ok',
        }
      },
    },
    { properties => [ 'textBody' ] },
    sub {
      my ($email) = @_;
      jcmp_deeply(
        $email->{textBody},
        [ superhashof({ type => 'text/plain' }) ],
        "the text/plain part still exists",
      );
    },
    "partId missing from bodyValues",
  );
};
