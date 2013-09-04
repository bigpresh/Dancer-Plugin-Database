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
        'Test::More' => 0,
        'Dancer::Plugin::Database::Core' => '0.04',
        'Dancer2'     => '0.09',
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
