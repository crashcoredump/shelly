package App::shelly::config;

use strict;
use warnings;
use Exporter::Lite;
use Path::Class qw(dir);

our @EXPORT_OK = qw(config config_path shelly_path local_path);

my $local_base_path = $ENV{HOME} . '/.shelly/';

sub local_path {
    return $local_base_path . $_[0];
}

sub config_path {
    return local_path('config');
}

sub shelly_path {
    if (exists $ENV{SHELLY_PATH}) {
        return $ENV{SHELLY_PATH};
    }
    if (-e local_path('shelly/')) {
        return local_path('shelly/')
    }
}

sub config {
    my $config_file = &config_path;

    my $config =
      -e $config_file
      ? do $config_file
      : {};

    return $config;
}

1;
