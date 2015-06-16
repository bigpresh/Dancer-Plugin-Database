use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Dancer::Plugin::Database::Core',
    AUTHOR           => q{David Precious <davidp@preshweb.co.uk>},
    VERSION_FROM     => 'lib/Dancer/Plugin/Database/Core.pm',
    ABSTRACT_FROM    => 'lib/Dancer/Plugin/Database/Core.pm',
    LICENSE          => 'artistic_2',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'DBI'        => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'Dancer-Plugin-Database-Core-*' },
    META_MERGE =>
              {
              "meta-spec" => { version => 2 },
              bugtracker  => {
                web => 'https://github.com/bigpresh/Dancer-Plugin-Database/issues',
               },
               resources =>
               {
                repository => 
                {
                 type => 'git',
                 web => 'https://github.com/bigpresh/Dancer-Plugin-Database',
                },
               },
              },
);
