package CatalystX::Controller::Verifier;

use strict;
use warnings;

use Moose::Role;

use Carp;
use Scalar::Util qw/blessed refaddr/;
use Data::Manager;

# ABSTRACT: Moose Role for verifying request parameters on a per action basis.

=head1 SYNOPSIS

 package MyApp::Controller::Foo;

 use Moose;
 BEGIN { extends 'Catalyst::Controller'; }

 with 'CatalystX::Controller::Verifier';

 __PACKAGE__->config(
    'verifiers' => {
        # The action name
        'search' => {
            filters => [ 'trim' ],
            # Just a plain Data::Verifier profile here:
            page => {
                type => 'Int',
                post_check => sub { shift->get_value('page') > 0 }
            },
            query => {
                type     => 'Str',
                required => 1,
            }
        },
    },
    # Additional options can be passed in:

    # If verification fails, detach to the 'bad_args' action
    'detach_on_failure' => 'bad_args',

    # If you want to override where the Data::Manager objects get tucked away:
    '_verifier_stash_key' => 'a secret garden',
 );

 sub search : Local {
     my ( $self, $c ) = @_;
     my $results = $self->verify( $c );
     
     $c->model('Search')->search(
        $results->get_value('page') || 1,
        $results->get_value('query')
     );
 }

If you run C<verify> in an action that does not have a profile, this will
throw an exception informing you of your transgressions.

But wait, there's more! Data::Verifier allows you to also define coercions.

=head1 COERCE YOUR PARAMETERS

So, in the above example lets say you wanted to parse your search query using
L<Search::Query>. Piece of cake!

 use Search::Query;

 __PACKAGE__->config(
    'verifiers' => {
        # The action name
        'search' => {
            # ... include the rest from synopsis ...
            query => {
                type     => 'Search::Query',
                required => 1,
                coercion => Data::Verifier::coercion(
                    from => 'Str',
                    via  => sub { Search::Query->parser->parse($_) }
                )
            }
        },
    }
 );

 sub search : Local {
     my ( $self, $c ) = @_;

     my $results = $self->verify( $c );
     
     $results->get_value('query');          # isa Search::Query object now!
     $results->get_original_value('query'); # Still valid
 }

=head1 MESSAGES

Got a validation error? Well, L<Data::Manager> covers that, too.

The messages method will return a L<Message::Stack> specific to that action.

 sub search : Local {
     my ( $self, $c ) = @_;

     my $results = $self->verify($c);
     unless ( $results->success ) {
         # Returns a Message::Stack for the action
         $self->messages($c);

         # Returns a Message::Stack for the 'search' scope
         $self->messages('search');

         # Returns a Message::Stack for the controller
         $self->messages;
     }
 }

=head1 LIFECYCLE

Each controller gets its own Data::Manager per request. This is probably not
blindly fast. It lives in the stash

=cut

has 'verifiers' => (
    is => 'rw',
    isa => 'HashRef[HashRef]'
);

has '_verifier_stash_key' => (
    is      => 'ro',
    isa     => 'Str',
    default => '_verifier_stash'
);

has 'detach_on_failure' => (
    is  => 'rw',
    isa => 'Str',
    clearer   => 'clear_detach_on_failure',
    predicate => 'has_detach_on_failure',
);

sub verify {
    my ( $self, $c ) = @_;
    my $params = $c->req->params;

    # Should always be blessed, but you never know.
    my $key = blessed $self ? refaddr $self : $self;
    my $dm  = $c->stash->{ $self->_verifier_stash_key }->{ $key };
    if ( not $dm ) {
        $dm = $self->_build_data_manager;
        $c->stash->{ $self->_verifier_stash_key }->{ $key } = $dm;
    }
    my $results = $dm->verify($c->action->name, $params);

    if ( not $results->success and $self->has_detach_on_failure ) {
        my $detach = $c->controller->action_for( $self->detach_on_failure );
        if ( not $detach ) {
            croak "Invalid detach action specified, " . $c->controller . " does not have an action '" . $self->detach_on_failure . "'.";
        }
        $c->detach($detach, [ $results ]);
    }

    return $results;
}

sub messages {
    my ( $self, $scope ) = @_;
    my $dm  = $c->stash->{ $self->_verifier_stash_key }->{ $key };
    # Return an empty stack if no DM
    return Message::Stack->new unless defined $dm;

    if ( defined $scope and blessed $scope )
        if ( $scope->isa('Catalyst') ) {
            $scope = $scope->action->name;
        }
        elsif ( $scoppe->isa('Catalyst::Action') ) {
            $scope = $scope->name;
        }
    }
    return $scope ? $dm->messages_for_scope($scope) : $dm->messages;
}

sub _build_data_manager {
    my ( $self ) = @_;

    my $verifiers = $self->verifiers;
    my %profiles  = ();
    foreach my $scope ( keys %$verifiers ) {
        $profiles{$scope} = Data::Verifier->new( $verifiers->{$scope} );
    }

    return Data::Manager->new(
        verifiers => \%profiles
    );
}

no Moose::Role;
1;
