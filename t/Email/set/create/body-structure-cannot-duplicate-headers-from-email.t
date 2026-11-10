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

  # RFC 8621 S4.6: a header on the root bodyStructure part "MUST NOT" also be
  # defined on the Email; for a single-part message they are the same header
  # block.
  email_create_invalid_or_repaired(
    $tester,
    {
      mailboxIds => { $mbox->id => \1, },
      'header:foo' => 'bar',
      bodyStructure => {
        partId => 'text',
        type   => 'text/plain',
        'header:foo' => 'bar',
      },
      bodyValues => {
        text => {
          value => 'ok',
        }
      },
    },
    { properties => [ 'header:foo:asText:all' ] },
    sub {
      my ($email) = @_;
      jcmp_deeply($email->{'header:foo:asText:all'}, [ 'bar' ], "foo appears once");
    },
    "header on both the Email and its bodyStructure",
  );
};
