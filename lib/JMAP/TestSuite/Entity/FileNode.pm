package JMAP::TestSuite::Entity::FileNode;
use Moose;
use Carp ();
use JMAP::TestSuite::Util qw(batch_ok fetch_session);
use Test::More;
use feature qw(state);
with 'JMAP::TestSuite::Entity' => {
  singular_noun => 'fileNode',
  properties  => [ qw(
    id
    parentId
    blobId
    target
    size
    name
    mediaType
    created
    modified
    accessed
    changed
    executable
    isSubscribed
    myRights
    shareWith
    role
  ) ],
};

my $CAP = 'urn:ietf:params:jmap:filenode';

for my $f (qw(
  mayRead
  mayAddChildren
  mayRename
  mayDelete
  mayModifyContent
  mayShare
)) {
  no strict 'refs';

  *{$f} = sub {
    Carp::croak("Cannot assign a value to a read-only accessor") if @_ > 1;
    return $_[0]->_props->{myRights}{$f};
  };
}

# The account's urn:ietf:params:jmap:filenode capability object.
sub capability {
  my ($class, $account) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my $session = fetch_session($account->tester) or return;
  return $session->{accounts}{ $account->accountId }{accountCapabilities}{$CAP};
}

# A fresh, uniquely named directory to work in.  It is created at the top
# level when the account allows that (draft "mayCreateTopLevelFileNode"),
# otherwise under the first top-level directory that grants
# mayAddChildren.  Returns the directory's entity.
sub scratch_dir {
  my ($class, $account, $arg) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  state $inc = 0;

  my $cap = $class->capability($account) or Carp::confess("no $CAP account capability");
  my $parentId;
  unless ($cap->{mayCreateTopLevelFileNode}) {
    my $res = $account->tester->request([
      [ 'FileNode/query' => { filter => { isTopLevel => JSON::true } }, 'q' ],
      [ 'FileNode/get'   => { '#ids' => { resultOf => 'q', name => 'FileNode/query', path => '/ids' } }, 'g' ],
    ]);
    my ($parent) = grep {; ($_->{'@type'} // '') eq 'Directory' && $_->{myRights}{mayAddChildren} }
                   @{ $res->sentence(1)->arguments->{list} || [] };
    Carp::confess("no top-level directory grants mayAddChildren") unless $parent;
    $parentId = $parent->{id};
  }

  return $class->create_node($account, {
    '@type'  => 'Directory',
    name     => "jmts $^T.$$." . $inc++,
    %{ $arg || {} },
    parentId => $parentId,
  });
}

sub create_node {
  my ($class, $account, $arg) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $batch = $account->create_batch(fileNode => { x => $arg });
  batch_ok($batch);
  ok($batch->is_entirely_successful, "created FileNode '$arg->{name}'")
    or diag explain $batch->all_results;
  return $batch->result_for('x');
}

# A child of this directory: { name => ..., content => ..., mediaType => ... }
# makes a File (the content is uploaded first), and no content a Directory.
# draft-ietf-jmap-filenode-20 S3.1.1: @type "MUST be provided on creation".
sub add_node {
  my ($self, $arg) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my %create = %$arg;
  if (defined(my $content = delete $create{content})) {
    my $blob = $self->tester->upload({
      accountId => $self->accountId,
      type      => $create{mediaType} // 'application/octet-stream',
      blob      => \$content,
    });
    $create{blobId} = $blob->blobId;
    $create{mediaType} //= 'application/octet-stream';
    $create{'@type'} //= 'File';
  }
  $create{'@type'} //= 'Directory';
  return ref($self)->create_node($self->account, { %create, parentId => $self->id });
}

no Moose;
__PACKAGE__->meta->make_immutable;
