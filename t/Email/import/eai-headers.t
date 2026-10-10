use jmaptest;
use utf8;
use Encode qw(encode_utf8);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mailbox = $account->create_mailbox;
  my $subject = "Grüße aus Köln, 東京 $$";
  my $message = join "\r\n",
    "From: Jörg Müller <jörg\@bücher.example>",
    "To: 田中 <田中\@例え.jp>",
    "Subject: $subject",
    "Message-Id: <eai.$$." . time . "\@example.com>",
    "Date: Mon, 02 Mar 2020 10:20:30 +0000",
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=utf-8",
    "",
    "Hallo.",
    "";

  my $blob = $tester->upload({
    accountId => $account->accountId,
    type      => 'message/rfc822',
    blob      => \encode_utf8($message),
  });
  ok($blob->is_success, 'uploaded an EAI message');

  # RFC 8621 S4.8: "The server MUST support messages with Email Address
  # Internationalization (EAI) headers [RFC6532]."
  my $res = $tester->request([[
    "Email/import" => {
      emails => {
        new => { blobId => $blob->blobId, mailboxIds => { $mailbox->id => jtrue } },
      },
    },
  ]]);
  my $id = $res->single_sentence('Email/import')->arguments->{created}{new}{id};
  ok($id, 'imported the message') or return diag explain $res->as_stripped_triples;

  # RFC 8621 does not say which form an internationalised domain comes back
  # in, so accept either the UTF-8 or the ASCII xn-- form.
  $tester->request_ok(
    [ "Email/get" => { ids => [ $id ], properties => [ qw(subject from to) ] } ],
    superhashof({
      list => [ {
        id      => $id,
        subject => $subject,
        from    => [ {
          name  => 'Jörg Müller',
          email => any('jörg@bücher.example', 'jörg@xn--bcher-kva.example'),
        } ],
        to      => [ {
          name  => '田中',
          email => any('田中@例え.jp', '田中@xn--r8jz45g.jp'),
        } ],
      } ],
    }),
    'UTF-8 subject and addresses read back intact',
  );
};
