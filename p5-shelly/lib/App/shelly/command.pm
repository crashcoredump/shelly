package App::shelly::command;

use strict;
use warnings;
use Path::Class qw(dir);

use App::shelly::config qw(config shelly_path);

sub new {
    my ($class, %args) = @_;

    return bless {
        verbose  => $args{verbose},
        options  => [],
    }, $class;
}

sub add_option {
    my $self = shift;
    push @{ $self->{options} }, @_;
}

sub add_eval_option {
    my ($self, $command) = @_;
    $self->add_option('-e', $command);
}

sub load_shelly {
    my ($self) = @_;

    if (my $shelly_path = shelly_path) {
        $shelly_path = dir($shelly_path)->absolute;
        $shelly_path =~ s!/?$!/!;
        $self->add_eval_option("(require (quote asdf))");
        $self->add_eval_option(qq'(push #P"$shelly_path" asdf:*central-registry*)');
    }

    # NOTE: Mysteriously, this doesn't work on Clozure CL, so loading Shelly as an eval option.
    #$self->add_option('-L', 'shelly');
    $self->add_eval_option(<<END_OF_LISP);
(let ((*standard-output* (make-broadcast-stream)) #+allegro(*readtable* (copy-readtable)))
  (handler-case #+quicklisp (ql:quickload :shelly) #-quicklisp (asdf:load-system :shelly)
    (#+quicklisp ql::system-not-found #-quicklisp asdf:missing-component (c)
     (format *error-output* "~&Error: ~A~&" c)
     #+quicklisp
     (format *error-output* "~&Try (ql:update-all-dists) to ensure your dist is up to date.~%")
     #+allegro (excl:exit 1 :quiet t)
     #+sbcl    (sb-ext:exit)
     #-(or allegro sbcl) (quit)))
  (values))
END_OF_LISP
    $self->add_eval_option('(shelly.util::shadowing-use-package :shelly)');
}

sub check_shelly_version {
    my ($self) = @_;
    if (config->{version}) {
        $self->add_eval_option(qq((shelly.util::check-version "@{[ config->{version} ]}")));
    }
}

sub add_load_path {
    my ($self, $directories) = @_;

    if (@$directories) {
        $self->add_eval_option(
            sprintf(
                "(shelly.util::add-load-path (list %s))",
                (join ' ', (map { qq{#P"$_"} } @$directories))
            )
        );
    }
}

sub load_libraries {
    my ($self, $libraries) = @_;

    if (@$libraries) {
        $self->add_option('-L', $_) for @$libraries;
    }
}

sub quit_lisp {
    $_[0]->add_eval_option('(swank-backend:quit-lisp)');
}

sub run_shelly_command {
    my ($self, $args) = @_;

    my @args = @$args;
    my $eval_expr =
        sprintf '(shelly.core::interpret (list %s) :verbose %s)',
            ( join " ", ( map { s/"/\\"/g;"\"$_\"" } @args ) ),
                $self->{verbose} ? 't' : 'nil';
    $self->add_eval_option($eval_expr);
    $self->quit_lisp;
}

sub arrayfy {
    my ($self) = @_;

    return ('cl', @{ $self->{options} });
}

sub stringify {
    my ($self) = @_;

    return join ' ', $self->arrayfy;
}

1;
