# Copyright (C) 2009 David Caldwell and Jim Radford, All Rights Reserved. -*- cperl -*-
package JavaScript::Hash; use warnings; use strict;
our $VERSION = '0.9.0';

use List::Util qw(max);
use JavaScript::Minifier::XS qw(minify);
use Digest::MD5 qw(md5_hex);
use File::Basename;
use File::Slurp qw(read_file write_file);

sub max_timestamp(@) { max map { (stat $_)[9] || 0 } @_ } # Obviously 9 is mtime

sub process_includes($;$);
sub process_includes($;$) {
    my ($filename, $referrer) = @_;
    my $blob = '';
    my @deps = ($filename);
    open my $js, "<", $filename or die "include $filename not found".($referrer?" at $referrer\n":"\n");
    my $line=0;
    while (<$js>) {
        $line++;
        if (/^#include\s+"([^"]+)"/) {
            my ($b,@d) = process_includes($1, "$filename:$line");
            $blob .= $b;
            push @deps, @d;
        } else {
            $blob .= $_;
        }
    }
    return ($blob, @deps);
}

use JSON qw(to_json from_json);

sub hash {
    my ($config, $name) = @_;

    my $script;
    if (   !($script = $config->{cache}->{$name})
        || ! -f $script->{path}
        || max_timestamp(@{$script->{deps}}) > $script->{timestamp}) {
        my $base = fileparse $name, ".js";
        my ($single_blob, @deps) = process_includes($name);
        my $minified = $config->{minify} ? minify($single_blob) : $single_blob;
        my $hash = md5_hex($minified);
        $config->{cache}->{$name} = $script = { deps => \@deps,
                                                name => "$base-$hash.js",
                                                path => "$config->{cache_dir}/$base-$hash.js",
                                                hash => $hash,
                                                timestamp => max_timestamp(@deps) };
        if (! -f $script->{path}) {
          mkdir $config->{cache_dir};
          write_file($script->{path},       { atomic => 1 }, $minified) or die "couldn't cache $script->{path}";
          write_file($config->{cache_file}, { atomic => 1 }, to_json($config->{cache}, {pretty => 1})) or warn "Couldn't save cache control file";
        }
    }
    $script->{name};
}

sub new {
    my $class = shift;
    my $config = bless { cache_dir => 'js',
                         minify    => 1,
                         @_
                       }, $class;
    $config->{cache_file} ||= "$config->{cache_dir}/cache.json";
    $config->{cache} = from_json( read_file($config->{cache_file}) ) if -f $config->{cache_file};
    $config;
}

1;

__END__

=head1 NAME

JavaScript::Hash - Compact and cache javascript files based on the hash of their contents.

=head1 SYNOPSIS

  use JavaScript::Hash;

  my $jsh = JavaScript::Hash->new();

  my $hashed_minified_path = $jsh->hash("my_javascript_file.js");
  # returns "my_javascript_file-7f4539486f2f6e65ef02fe9f98e68944.js"

  # If you are using Template::Toolkit you may want something like this:
  $template->process('template.tt2', {
      script => sub {
          my $path = $jsh->hash($_[0]);
          "<script src=\"js/$path\" type=\"text/javascript\"></script>\n";
      } } ) || die $template->error();

  # And in your template.tt2 file:
  #    [% script("myscript.js") %]
  # which will get replaced with something like:
  #    <script src="js/myscript-708b88f899939c4adedc271d9ab9ee66.js"
  #            type="text/javascript"></script>

=head1 DESCRIPTION

JavaScript::Hash is an automatic versioning scheme for Javascript based on
the hash of the contents of the Javascript files themselves. It aims to be
painless for the developer and very fast.

JavaScript::Hash solves the problem in web development where you update some
Javascript files on the server and the end user ends up with mismatched
versions because of browser or proxy caching issues. By referencing your
Javascript files by their MD5 hash, the browser is unable to to give the end
user mismatched versions no matter what the caching policy is.

=head1 HOW TO USE IT

The best place to use JavaScript::Hash is in your HTML template code. While
generating a page to serve to the user, call the hash() method for each
Javascript file you are including in your page. The hash() method will
return the name of the newly hashed file. You should use this name in the
<script> tag of the page.

This means that when the browser gets the page you serve, it will have
references to specific versions of Javascript files.

=head1 METHODS

=over 4

=item B<C<new(%options)>>

Initializes a new cache object. Available options and their defaults:

=over 4

=item C<< cache_dir => 'js' >>

Where to put the resulting minified js files.

=item C<< minify => 1 >>

Whether or not to minify the Javascript.

=item C<< cache_file => "$cache_dir/cache.json" >>

Where to put the cache control file.

=back

=item B<C<hash($path_to_js_file)>>

This method...

=over

=item 1

Reads the Javascript file into memory. While reading it understands C
style "#include" directives so you can structure the code nicely.

=item 2

Uses L<JavaScript::Minifier::XS> to minify the resulting code. If the minify
option is set to 0 then it doesn't actually minify the code. This is useful
for debugging.

=item 3

Calculates the MD5 hash of the minified code.

=item 4

Saves the minified code to a cache directory where it is named based on
its hash value which makes the name globally unique (it also keeps it's
original name as a prefix so debugging is sane).

=item 5

Keeps track of the original script name, the minified script's globally
unique name, and the dependencies used to build the image. This is stored in
a hash table and also saved to the disk for future runs.

=item 6

Returns the name of the minified file that was stored in step 4. This name
does not include the cache directory path because its physical file system
path does not necessarily relate to its virtual server path.

=back

There's actually a step 0 in there too: If the original Javascript file name
is found in the hash table then it quickly stats its saved dependencies to
see if they are newer than the saved minified file. If the minified file is
up to date then steps 1 through 5 are skipped.

=back

=head1 FURTHER DISCUSSION ABOUT THIS TECHNIQUE

=head2 It keeps the Javascript files in sync

When the user refreshes the page they will either get the page from their
browser cache or they will get it from our site. No matter where it came
from the Javascript files it references are now uniquely named so that it is
impossible for the files to be out of date from each other.

That is, if you get the old HTML file you will reference all the old named
Javascript files and everything will be mutually consistent (even though it
is out of date). If you get the new HTML file it guarantees you will have to
fetch the latest Javascript files because the new HTML only references the
new hashed names that aren't going to be in your browser cache.

=head2 It's fast.

Everything is cached so it only does the minification and hash calculations
once per file. More importantly the cached dir can be statically served by
the web server so it's exactly as fast as it would be if you served the .js
files without any preprocessing. All this technique adds is a couple
filesystem stats per page load, which isn't much (Linux can do something
like a million stats per second).

=head2 It's automatic.

If you hook in through L<Template::Toolkit> then there's no script to
remember to run when you update the site. When the template generates the
HTML, the L<JavaScript::Hash> code lazily takes care of rebuilding any
files that may have gone out of date.

=head2 It's stateless.

It doesn't rely on incrementing numbers (”js/v10/script.js” or even
“js/script-v10.js”). We considered this approach but decided it was actually
harder to implement and had no advantages over the way we chose to do
it. This may have been colored by our choice of version control systems (we
love the current wave of DVCSes) where monotonically increasing version
numbers have no meaning.

=head2 It allows aggressive caching.

Since the files are named by their contents' hash, you can set the cache
time on your web server to be practically infinite.

=head2 It's very simple to understand.

It took less than a page of Perl code to implement the whole thing and it
worked the first time with no bugs. I believe it's taken me longer to write
this than it took to write the code (granted I'd been thinking about it for
a long time before I started coding).

=head2 No files are deleted.

The old js files are not automatically deleted (why bother, they are tiny)
so people with extremely old HTML files will not have inconsistent pages
when they reload. However:

=head2 The cache directory is volatile.

It's written so we can delete the entire cache dir at any point and it will
just recreate what it needs to on the next request. This means there's
no setup to do in your app.

=head2 You get a bit of history.

Do a quick C<ls -lrt> of the directory and you can see which scripts have
been updated recently and in what order they got built.

=head1 SEE ALSO

This code was adapted from the code we wrote for our site
L<http://greenfelt.net/>. Here is our original blog post talking about the technique:
L<http://blog.greenfelt.net/2009/09/01/caching-javascript-safely/>

=head1 COPYRIGHT

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

Copyright (C) 2009 David Caldwell and Jim Radford.

=head1 AUTHOR

=over

=item *

David Caldwell <david@porkrind.org>

=item *

Jim Radford <radford@blackbean.org>

=back

=cut
