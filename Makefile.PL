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
        # We need support for "var("foo" => "bar")".
        # Not sure if this is the correct version
        'Dancer'     => 1.3059,
        'DBI'        => 0,
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
