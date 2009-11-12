#  Copyright (c) 2009 David Caldwell,  All Rights Reserved. -*- cperl -*-

use strict;
use warnings;

use Test::More tests => 13;
use JavaScript::Hash;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);

my $dir = tempdir();
sub file_with_contents($$) {
    my $name = "$dir/$_[0]";
    write_file($name, $_[1]) or die "$name: $!";
    $name
}

my $cache_dir = 'js-test-cache';
my $jsh = JavaScript::Hash->new(cache_dir => $cache_dir);

my $filea = file_with_contents("a.js", <<EOF);
var a=1;
var b=2;
var c=3;
EOF

my $hasheda = $jsh->hash($filea);
is($hasheda, 'a-e14548d326ca1e7f05661a9b3d68419b.js',                    'hashed filename');
ok(-f "$cache_dir/a-e14548d326ca1e7f05661a9b3d68419b.js",                'hashed file was written');
ok(-f "$cache_dir/cache.json",                                           'cache file was written');

my $fileb = file_with_contents("b.js", <<EOF);
#include "$filea"
var d=1;
var e=2;
var f=3;
EOF

my $hashedb = $jsh->hash($fileb);
is($hashedb, 'b-20b3d0cc5dc4a21c95c15e17a3c20942.js',                    'hashed filename w/include');
ok(-f "$cache_dir/b-20b3d0cc5dc4a21c95c15e17a3c20942.js",                'hashed file w/include was written');

sleep(1); # Weak! mtime must not be very high resolution.
write_file($filea, <<EOF);
var a=-1;
var b=-2;
var c=-3;
EOF
my $hasheda2 = $jsh->hash($filea);
my $hashedb2 = $jsh->hash($fileb);
is($hasheda2, 'a-61dbd4778883c6e1e4d174a3e0092683.js',                    'mtime cache invalidation');
is($hashedb2, 'b-845e47b03551efc670490ab228698f49.js',                    'mtime cache invalidation on included file');

my $old_moda = -M "$cache_dir/a-61dbd4778883c6e1e4d174a3e0092683.js";
my $old_modb = -M "$cache_dir/b-845e47b03551efc670490ab228698f49.js";
sleep(1); # Stupid mtime again
my $jsh2 = JavaScript::Hash->new(cache_dir => $cache_dir);
my $hasheda3 = $jsh2->hash($filea);
my $hashedb3 = $jsh2->hash($fileb);
is($hasheda3, 'a-61dbd4778883c6e1e4d174a3e0092683.js',                      'used json.cache');
is($hashedb3, 'b-845e47b03551efc670490ab228698f49.js',                      'used json.cache on included file');
ok($old_moda == -M "$cache_dir/a-61dbd4778883c6e1e4d174a3e0092683.js",      'used json.cache to know not to rebuild minified file');
ok($old_modb == -M "$cache_dir/b-845e47b03551efc670490ab228698f49.js",      'used json.cache to know not to rebuild minified file w/include');

unlink("$cache_dir/a-61dbd4778883c6e1e4d174a3e0092683.js");
my $hasheda4 = $jsh2->hash($filea);
is($hasheda4, 'a-61dbd4778883c6e1e4d174a3e0092683.js',                      'handled unlinked cached file');
ok(-f "$cache_dir/a-61dbd4778883c6e1e4d174a3e0092683.js",                   'hashed file was written after unlink');
