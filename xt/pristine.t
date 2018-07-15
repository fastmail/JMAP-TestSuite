use strict;
use warnings;
use Test::Routine;
use Test::Routine::Util;

with 'JMAP::TestSuite::Tester';

use JMAP::TestSuite::Util qw(batch_ok);

use Test::Deep ':v1';
use Test::Deep::JType;
use Test::More;
use JSON qw(decode_json);
use JSON::Typist;
use Test::Abortable;

test "Ensure pristine accounts are pristine" => { requires_pristine => 1 } => sub {
  my ($self) = @_;

  # Cheat - just make sure we don't get a reused account
  isnt(
    $self->context->accountId,
    $self->server->pristine_account->accountId,
    'Got unique accountIds from pristine_account',
  );
};

run_me;
done_testing;
