use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Dancer::Plugin::Database',
    AUTHOR              => q{David Precious <davidp@preshweb.co.uk>},
    VERSION_FROM        => 'lib/Dancer/Plugin/Database.pm',
    ABSTRACT_FROM       => 'lib/Dancer/Plugin/Database.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'Dancer::Plugin::Database::Core' => '0.04',
        # Need support for Dancer2-compatible stuff
        'Dancer'     => 1.3099,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Dancer-Plugin-Database-*' },
    META_MERGE => {
        resources => {
            repository => 'https://github.com/bigpresh/Dancer-Plugin-Database',
            bugtracker => 'https://github.com/bigpresh/Dancer-Plugin-Database/issues',
            homepage   => 'https://github.com/bigpresh/Dancer-Plugin-Database/',
        },
    },
);
