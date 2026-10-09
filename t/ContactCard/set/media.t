use jmaptest;
use Data::GUID qw(guid_string);
use MIME::Base64 qw(decode_base64);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:contacts',
  );

  # A 1x1 PNG, from RFC 9404 S4.1.1.
  my $png_b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX/AAAZ4gk3'
              . 'AAAAAXRSTlN/gFy0ywAAAApJREFUeJxjYgAAAAYAAzY3fKgAAAAASUVORK5CYII=';
  my $png = decode_base64($png_b64);

  my $ab = $account->create_address_book;

  my $create = sub {
    my ($media) = @_;
    my $res = $tester->request([[
      "ContactCard/set" => {
        create => {
          c1 => {
            '@type'        => 'Card',
            version        => '1.0',
            uid            => "urn:uuid:" . lc guid_string(),
            name           => { full => "Media Test" },
            addressBookIds => { $ab->id => \1 },
            media          => { m1 => $media },
          },
        },
      },
    ]]);
    ok($res->is_success, "ContactCard/set") or diag explain $res->response_payload;
    return $res->single_sentence("ContactCard/set")->arguments;
  };

  my $media_of = sub {
    my ($id) = @_;
    my $res = $tester->request([[
      "ContactCard/get" => { ids => [ $id ], properties => [ 'media' ] },
    ]]);
    return $res->single_sentence("ContactCard/get")->arguments->{list}[0]{media}{m1};
  };

  # RFC 9610 S3: clients "MAY send a blobId instead of the uri property".
  subtest "photo given by blobId" => sub {
    my $blob = $tester->upload({
      accountId => $account->accountId,
      type      => 'image/png',
      blob      => \$png,
    });

    my $args = $create->({ kind => 'photo', blobId => $blob->blobId, mediaType => 'image/png' });
    my $id = $args->{created}{c1}{id};
    ok($id, "card created") or diag(explain($args)), return;

    jcmp_deeply(
      $media_of->($id),
      superhashof({ kind => 'photo', blobId => jstr, mediaType => 'image/png' }),
      "media has a blobId and mediaType",
    );
  };

  # RFC 9610 S3: a "data:" URI "SHOULD" come back as a blobId, and then "The
  # mediaType property MUST also be set".
  subtest "photo given as a data: URI" => sub {
    my $args = $create->({ kind => 'photo', uri => "data:image/png;base64,$png_b64" });
    my $id = $args->{created}{c1}{id};
    ok($id, "card created") or diag(explain($args)), return;

    jcmp_deeply(
      $media_of->($id),
      any(
        superhashof({ kind => 'photo', blobId => jstr, mediaType => 'image/png' }),
        superhashof({ kind => 'photo', uri => "data:image/png;base64,$png_b64" }),
      ),
      "media has a blobId and mediaType, or the original uri",
    );
  };

  # RFC 9610 S3.5: the server "MUST reject attempts to set a file that is not
  # a recognised image type as the photo for a card".
  subtest "photo that is not an image" => sub {
    my $blob = $tester->upload({
      accountId => $account->accountId,
      type      => 'text/plain',
      blob      => \"This is plain text, not an image.\n",
    });

    my $args = $create->({ kind => 'photo', blobId => $blob->blobId });
    ok(!$args->{created}{c1}, "card not created") or diag explain $args;
    jcmp_deeply($args->{notCreated}{c1}, superhashof({ type => jstr }), "rejected with a SetError")
      or diag explain $args;
  };
};
