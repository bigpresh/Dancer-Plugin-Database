use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Dancer2::Plugin::Database',
    AUTHOR              => q{David Precious <davidp@preshweb.co.uk>},
    VERSION_FROM        => 'lib/Dancer2/Plugin/Database.pm',
    ABSTRACT_FROM       => 'lib/Dancer2/Plugin/Database.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Dancer2'                        => '0.166001',
        'Dancer::Plugin::Database::Core' => '0.16',
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
