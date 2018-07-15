package JMAP::TestSuite::JMAP::Tester::Wrapper;
use strict;
use warnings;

use Params::Util qw(_ARRAY0 _HASH);

use Moo;
use Test::More;
use Test::Deep::JType;

use feature qw(state);

extends 'JMAP::Tester';

has default_using => (
  is  => 'rw',
  isa => sub {
    die "must be an arrayref" unless _ARRAY0 $_[0];
  },
  default => sub {
    [ "urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  },
);

around request => sub {
  my ($orig, $self, $input_request) = @_;

  my $request;

  if (_ARRAY0($input_request)) {
    $request = {
      methodCalls => $input_request,
    },
  } else {
    $request = $input_request;
  }

  unless (
       exists $request->{using}
    || delete $request->{no_using}
  ) {
    $request->{using} = $self->default_using;
  }

  return $orig->($self, $request);
};

sub request_ok {
  my ($self, $input_request, $expect_paragraphs, $desc) = @_;

  # Allow ->request_ok([ foo => { ... } ], superhashof({...}), ...)
  if (
         _ARRAY0($input_request)
    && ! _ARRAY0($input_request->[0])
    && ! _ARRAY0($expect_paragraphs)
  ) {
    $input_request = [ $input_request ];
    $expect_paragraphs = [[ $expect_paragraphs ]];
  }

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  subtest "$desc" => sub {
    state $ident = 'a';
    my %seen;
    my @suffixed;
    my @req_client_ids;
    my @req_sentence_names;
    my $failures;

    my $request = _ARRAY0($input_request)
                ? { methodCalls => $input_request }
                : { %$input_request };

    for my $call (@{ $request->{methodCalls} }) {
      my $cid;

      my $copy = [ @$call ];
      if (defined $copy->[2]) {
        $seen{$call->[2]}++;

        $cid = $call->[2];
      } else {
        my $next;
        do { $next = $ident++ } until ! $seen{$ident}++;
        $cid = $copy->[2] = $next;
      }

      push @suffixed, $copy;
      push @req_client_ids, $cid;

      push @req_sentence_names, $call->[0];
    }

    $request->{methodCalls} = \@suffixed;

    my $res = $self->request($request);

    # Check success, give diagnostic on failure
    ok($res->is_success, 'JMAP request succeeded')
      or die "Request failed: " . $res->http_response->as_string;

    for my $expect_para (@$expect_paragraphs) {
      my $cid = shift @req_client_ids;
      my $name = shift @req_sentence_names;

      my $res_para = $res->paragraph_by_client_id($cid);
      unless ($res_para) {
        die   "No paragraph for cid '$cid' in response to '$name'?: "
            . diag explain $res->as_stripped_triples;
      }

      while (@$expect_para) {
        # Allow:
        #
        #   [ superhashof({...}) ]
        #   [ name => superhashof({...}) ]
        #
        # In the first form, we will pick the name based off of the
        # matching request
        my ($expect_name, $expect_struct) = do {
          my $name_or_struct = shift @$expect_para;

          if (ref $name_or_struct) {
            ($name, $name_or_struct);
          } else {
            ($name_or_struct, shift @$expect_para);
          }
       };

        # Will croak if not found
        my $res_sentence = $res_para->sentence_named($expect_name);
        ok($res_sentence, "Found a sentence named $expect_name");

        jcmp_deeply(
          $res_sentence->arguments,
          $expect_struct,
          "Sentence for cid '$cid' in response to '$name' matches up"
        ) or $failures++;
      }
    }

    if ($failures) {
      diag explain $res->as_stripped_triples;
    }
  }
}

1;
