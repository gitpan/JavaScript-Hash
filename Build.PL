use Module::Build;
Module::Build->new(
    module_name => 'JavaScript::Hash',
    license     => 'perl',
    dist_author => 'David Caldwell <david@porkrind.org>',
    requires    => {
        File::Slurp => 0,
        JSON => 0,
        JavaScript::Minifier::XS => 0,
    },
)->create_build_script;
