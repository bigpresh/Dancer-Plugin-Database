use strict;
use warnings;
use ExtUtils::MakeMaker 6.48;

WriteMakefile(
    NAME                => 'Dancer2::Plugin::Database',
    AUTHOR              => q{David Precious <davidp@preshweb.co.uk>},
    VERSION_FROM        => 'lib/Dancer2/Plugin/Database.pm',
    ABSTRACT_FROM       => 'lib/Dancer2/Plugin/Database.pm',
    MIN_PERL_VERSION    => '5.010',
    LICENSE             => 'perl',
    PL_FILES            => {},
    PREREQ_PM => {
        'Dancer2'                        => '0.151000',
        'Dancer::Plugin::Database::Core' => '0.12',
    },
    TEST_REQUIRES => {
        'Test::More'            => 0,
        'HTTP::Request::Common' => 0,
        'Plack'                 => '1.0032',
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Dancer2-Plugin-Database-*' },
    META_MERGE => {
        resources => {
            repository => 'https://github.com/bigpresh/Dancer-Plugin-Database',
            bugtracker => 'https://github.com/bigpresh/Dancer-Plugin-Database/issues',
            homepage   => 'https://github.com/bigpresh/Dancer-Plugin-Database/',
        },
    },
);
