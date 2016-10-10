use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 140;

use Readonly;
use HTTP::HashServer;
use HTTP::Status qw(:constants);
use URI::Escape;
use Data::Dumper;

use MediaWords::Test::DB;

Readonly my $TEST_HTTP_SERVER_PORT => 9998;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::URL' );
}

sub test_get_url_host()
{
    eval { MediaWords::Util::URL::get_url_host( undef ) };
    ok( $@, 'Undefined parameter' );
    is( MediaWords::Util::URL::get_url_host( 'http://www.nytimes.com/' ), 'www.nytimes.com', 'www.nytimes.com' );
    is( MediaWords::Util::URL::get_url_host( 'http://obama:barack1@WHITEHOUSE.GOV/michelle.html' ),
        'whitehouse.gov', 'whitehouse.gov with auth' );
}

sub test_get_url_distinctive_domain()
{
    # FIXME - some resulting domains look funny, not sure if I can change them easily though
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://www.nytimes.com/' ),
        'nytimes.com', 'get_url_distinctive_domain() - nytimes.com' );
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://cyber.law.harvard.edu/' ),
        'law.harvard', 'get_url_distinctive_domain() - cyber.law.harvard.edu' );
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://www.gazeta.ru/' ),
        'gazeta.ru', 'get_url_distinctive_domain() - gazeta.ru' );
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://www.whitehouse.gov/' ),
        'www.whitehouse', 'get_url_distinctive_domain() - www.whitehouse' );
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://info.info/' ),
        'info.info', 'get_url_distinctive_domain() - info.info' );
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://blog.yesmeck.com/jquery-jsonview/' ),
        'yesmeck.com', 'get_url_distinctive_domain() - yesmeck.com' );
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://status.livejournal.org/' ),
        'livejournal.org', 'get_url_distinctive_domain() - livejournal.org' );

    # Make sure subroutine works with ap.org
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://ap.org/' ),                   'ap.org', 'ap.org #1' );
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://ap.org' ),                    'ap.org', 'ap.org #2' );
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://hosted.ap.org/foo/bar/baz' ), 'ap.org', 'ap.org #3' );

    # ".(gov|org|com).XX" exception
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'http://www.stat.gov.lt/' ),
        'stat.gov.lt', 'get_url_distinctive_domain() - www.stat.gov.lt' );

    # "wordpress.com|blogspot|livejournal.com|privet.ru|wikia.com|feedburner.com|24open.ru|patch.com|tumblr.com" exception
    is( MediaWords::Util::URL::get_url_distinctive_domain( 'https://en.blog.wordpress.com/' ),
        'en.blog.wordpress.com', 'get_url_distinctive_domain() - en.blog.wordpress.com' );

# FIXME - invalid URL
# is(MediaWords::Util::URL::get_url_distinctive_domain('http:///www.facebook.com/'), undef, 'get_url_distinctive_domain() - invalid facebook.com');
}

sub test_meta_refresh_url_from_html()
{
    my $html;
    my $base_url;
    my $expected_url;

    # No <meta http-equiv="refresh" />
    $html = <<EOF;
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = undef;
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'No <meta http-equiv="refresh" />' );

    # Basic HTML <meta http-equiv="refresh">
    $html = <<EOF;
        <HTML>
        <HEAD>
            <TITLE>This is a test</TITLE>
            <META HTTP-EQUIV="content-type" CONTENT="text/html; charset=UTF-8">
            <META HTTP-EQUIV="refresh" CONTENT="0; URL=http://example.com/">
        </HEAD>
        <BODY>
            <P>This is a test.</P>
        </BODY>
        </HTML>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Basic HTML <meta http-equiv="refresh">' );

    # Basic XHTML <meta http-equiv="refresh" />
    $html = <<EOF;
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content="0; url=http://example.com/" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Basic XHTML <meta http-equiv="refresh" />' );

    # Basic XHTML sans the seconds part
    $html = <<EOF;
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content="url=http://example.com/" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Basic XHTML sans the seconds part' );

    # Basic XHTML with quoted url
    $html = <<EOF;
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content="url='http://example.com/'" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Basic XHTML with quoted url' );

    # Basic XHTML with reverse quoted url
    $html = <<EOF;
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content='url="http://example.com/"' />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Basic XHTML with reverse quoted url' );

    # Relative path (base URL with trailing slash)
    $html = <<EOF;
        <meta http-equiv="refresh" content="0; url=second/third/" />
EOF
    $base_url     = 'http://example.com/first/';
    $expected_url = 'http://example.com/first/second/third/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Relative path (with trailing slash)' );

    # Relative path (base URL without trailing slash)
    $html = <<EOF;
        <meta http-equiv="refresh" content="0; url=second/third/" />
EOF
    $base_url     = 'http://example.com/first';
    $expected_url = 'http://example.com/second/third/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Relative path (without trailing slash)' );

    # Absolute path
    $html = <<EOF;
        <meta http-equiv="refresh" content="0; url=/first/second/third/" />
EOF
    $base_url     = 'http://example.com/fourth/fifth/';
    $expected_url = 'http://example.com/first/second/third/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ), $expected_url, 'Absolute path' );

    # Invalid URL without base URL
    $html = <<EOF;
        <meta http-equiv="refresh" content="0; url=/first/second/third/" />
EOF
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html ), undef, 'Invalid URL without base URL' );
}

sub test_link_canonical_url_from_html()
{
    my $html;
    my $base_url;
    my $expected_url;

    # No <link rel="canonical" />
    $html = <<EOF;
        <html>
        <head>
            <title>This is a test</title>
            <link rel="stylesheet" type="text/css" href="theme.css" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = undef;
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ),
        $expected_url, 'No <link rel="canonical" />' );

    # Basic HTML <link rel="canonical">
    $html = <<EOF;
        <HTML>
        <HEAD>
            <TITLE>This is a test</TITLE>
            <LINK REL="stylesheet" TYPE="text/css" HREF="theme.css">
            <LINK REL="canonical" HREF="http://example.com/">
        </HEAD>
        <BODY>
            <P>This is a test.</P>
        </BODY>
        </HTML>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ),
        $expected_url, 'Basic HTML <link rel="canonical">' );

    # Basic XHTML <meta http-equiv="refresh" />
    $html = <<EOF;
        <html>
        <head>
            <title>This is a test</title>
            <link rel="stylesheet" type="text/css" href="theme.css" />
            <link rel="canonical" href="http://example.com/" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ),
        $expected_url, 'Basic XHTML <link rel="canonical" />' );

    # Relative path (base URL with trailing slash -- valid, but not a good practice)
    $html = <<EOF;
        <link rel="canonical" href="second/third/" />
EOF
    $base_url     = 'http://example.com/first/';
    $expected_url = 'http://example.com/first/second/third/';
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ),
        $expected_url, 'Relative path (with trailing slash)' );

    # Relative path (base URL without trailing slash -- valid, but not a good practice)
    $html = <<EOF;
        <link rel="canonical" href="second/third/" />
EOF
    $base_url     = 'http://example.com/first';
    $expected_url = 'http://example.com/second/third/';
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ),
        $expected_url, 'Relative path (without trailing slash)' );

    # Absolute path (valid, but not a good practice)
    $html = <<EOF;
        <link rel="canonical" href="/first/second/third/" />
EOF
    $base_url     = 'http://example.com/fourth/fifth/';
    $expected_url = 'http://example.com/first/second/third/';
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ), $expected_url, 'Absolute path' );

    # Invalid URL without base URL
    $html = <<EOF;
        <link rel="canonical" href="/first/second/third/" />
EOF
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html ), undef, 'Invalid URL without base URL' );
}

sub test_url_and_data_after_redirects_http()
{
    eval { MediaWords::Util::URL::url_and_data_after_redirects( undef ); };
    ok( $@, 'Undefined URL' );

    eval { MediaWords::Util::URL::url_and_data_after_redirects( 'gopher://gopher.floodgap.com/0/v2/vstat' ); };
    ok( $@, 'Non-HTTP(S) URL' );

    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTTP redirects
    my $pages = {
        '/first'  => { redirect => '/second',                        http_status_code => HTTP_MOVED_PERMANENTLY },
        '/second' => { redirect => $TEST_HTTP_SERVER_URL . '/third', http_status_code => HTTP_FOUND },
        '/third'  => { redirect => '/fourth',                        http_status_code => HTTP_SEE_OTHER },
        '/fourth' => { redirect => $TEST_HTTP_SERVER_URL . '/fifth', http_status_code => HTTP_TEMPORARY_REDIRECT },
        '/fifth' => 'Seems to be working.'
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects,  $TEST_HTTP_SERVER_URL . '/fifth', 'URL after HTTP redirects' );
    is( $data_after_redirects, $pages->{ '/fifth' },             'Data after HTTP redirects' );
}

sub test_url_and_data_after_redirects_nonexistent()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # Nonexistent URL ("/first")
    my $pages = {};

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects,  $starting_url, 'URL after unsuccessful HTTP redirects' );
    is( $data_after_redirects, undef,         'Data after unsuccessful HTTP redirects' );
}

sub test_url_and_data_after_redirects_html()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';
    Readonly my $MAX_META_REDIRECTS => 7;    # instead of default 3

    # HTML redirects
    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
        '/second' => '<meta http-equiv="refresh" content="url=third" />',
        '/third'  => '<META HTTP-EQUIV="REFRESH" CONTENT="10; URL=/fourth" />',
        '/fourth' => '< meta content="url=fifth" http-equiv="refresh" >',
        '/fifth'  => 'Seems to be working too.'
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url, undef, $MAX_META_REDIRECTS );

    $hs->stop();

    is( $url_after_redirects,  $TEST_HTTP_SERVER_URL . '/fifth', 'URL after HTML redirects' );
    is( $data_after_redirects, $pages->{ '/fifth' },             'Data after HTML redirects' );
}

sub test_url_and_data_after_redirects_http_loop()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # "http://127.0.0.1:9998/third?url=http%3A%2F%2F127.0.0.1%2Fsecond"
    my $third = '/third?url=' . uri_escape( $TEST_HTTP_SERVER_URL . '/second' );

    # HTTP redirects
    my $pages = {

# e.g. http://rss.nytimes.com/c/34625/f/640350/s/3a08a24a/sc/1/l/0L0Snytimes0N0C20A140C0A50C0A40Cus0Cpolitics0Cobama0Ewhite0Ehouse0Ecorrespondents0Edinner0Bhtml0Dpartner0Frss0Gemc0Frss/story01.htm
        '/first' => { redirect => '/second', http_status_code => HTTP_SEE_OTHER },

        # e.g. http://www.nytimes.com/2014/05/04/us/politics/obama-white-house-correspondents-dinner.html?partner=rss&emc=rss
        '/second' => { redirect => $third, http_status_code => HTTP_SEE_OTHER },

# e.g. http://www.nytimes.com/glogin?URI=http%3A%2F%2Fwww.nytimes.com%2F2014%2F05%2F04%2Fus%2Fpolitics%2Fobama-white-house-correspondents-dinner.html%3Fpartner%3Drss%26emc%3Drss
        '/third' => { redirect => '/second', http_status_code => HTTP_SEE_OTHER }
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects, $TEST_HTTP_SERVER_URL . '/second', 'URL after HTTP redirect loop' );
}

sub test_url_and_data_after_redirects_html_loop()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTML redirects
    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third" />',
        '/third'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects, $TEST_HTTP_SERVER_URL . '/second', 'URL after HTML redirect loop' );
}

# Test if the subroutine acts nicely when the server decides to ensure that the
# client supports cookies (e.g.
# http://www.dailytelegraph.com.au/news/world/charlie-hebdo-attack-police-close-in-on-two-armed-massacre-suspects-as-manhunt-continues-across-france/story-fni0xs63-1227178925700)
sub test_url_and_data_after_redirects_cookies()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';
    Readonly my $TEST_CONTENT => 'This is the content.';

    Readonly my $COOKIE_NAME    => "test_cookie";
    Readonly my $COOKIE_VALUE   => "I'm a cookie and I know it!";
    Readonly my $DEFAULT_HEADER => "Content-Type: text/html; charset=UTF-8";

    # HTTP redirects
    my $pages = {
        '/first' => {
            callback => sub {
                my ( $self, $cgi ) = @_;

                my $received_cookie = $cgi->cookie( $COOKIE_NAME );

                if ( $received_cookie and $received_cookie eq $COOKIE_VALUE )
                {

                    TRACE "Cookie was set previously, showing page";

                    print "HTTP/1.0 200 OK\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "\r\n";
                    print $TEST_CONTENT;

                }
                else
                {

                    TRACE "Setting cookie, redirecting to /check_cookie";

                    print "HTTP/1.0 302 Moved Temporarily\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "Location: /check_cookie\r\n";
                    print "Set-Cookie: $COOKIE_NAME=$COOKIE_VALUE\r\n";
                    print "\r\n";
                    print "Redirecting to the cookie check page...";
                }
            }
        },

        '/check_cookie' => {
            callback => sub {

                my ( $self, $cgi ) = @_;

                my $received_cookie = $cgi->cookie( $COOKIE_NAME );

                if ( $received_cookie and $received_cookie eq $COOKIE_VALUE )
                {

                    TRACE "Cookie was set previously, redirecting back to the initial page";

                    print "HTTP/1.0 302 Moved Temporarily\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "Location: $starting_url\r\n";
                    print "\r\n";
                    print "Cookie looks fine, redirecting you back to the article...";

                }
                else
                {

                    TRACE "Cookie wasn't found, redirecting you to the /no_cookies page...";

                    print "HTTP/1.0 302 Moved Temporarily\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "Location: /no_cookies\r\n";
                    print "\r\n";
                    print 'Cookie wasn\'t found, redirecting you to the "no cookies" page...';
                }
            }
        },
        '/no_cookies' => "No cookie support, go away, we don\'t like you."
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects,  $starting_url, 'URL after HTTP redirects (cookie)' );
    is( $data_after_redirects, $TEST_CONTENT, 'Data after HTTP redirects (cookie)' );
}

sub test_http_urls_in_string()
{
    my $test_string;
    my $expected_urls;

    # Basic test
    $test_string = <<EOF;
        These are my favourite websites:
        * http://www.mediacloud.org/
        * http://cyber.law.harvard.edu/
        * about:blank
EOF
    $expected_urls = [ 'http://www.mediacloud.org/', 'http://cyber.law.harvard.edu/', ];
    cmp_bag( MediaWords::Util::URL::http_urls_in_string( $test_string ), $expected_urls,
        'test_http_urls_in_string - basic' );

    # Duplicate URLs
    $test_string = <<EOF;
        These are my favourite (duplicate) websites:
        * http://www.mediacloud.org/
        * http://www.mediacloud.org/
        * http://cyber.law.harvard.edu/
        * http://cyber.law.harvard.edu/
        * http://www.mediacloud.org/
        * http://www.mediacloud.org/
EOF
    $expected_urls = [ 'http://www.mediacloud.org/', 'http://cyber.law.harvard.edu/', ];
    cmp_bag( MediaWords::Util::URL::http_urls_in_string( $test_string ),
        $expected_urls, 'test_http_urls_in_string - duplicate URLs' );

    # No http:// URLs
    $test_string = <<EOF;
        This test text doesn't have any http:// URLs, only a ftp:// one:
        ftp://ftp.ubuntu.com/ubuntu/
EOF
    $expected_urls = [];
    cmp_bag( MediaWords::Util::URL::http_urls_in_string( $test_string ),
        $expected_urls, 'test_http_urls_in_string - no HTTP URLs' );

    # Erroneous input
    eval { MediaWords::Util::URL::http_urls_in_string( undef ); };
    ok( $@, 'test_http_urls_in_string - erroneous input' );
}

sub test_all_url_variants($)
{
    my ( $db ) = @_;

    my @actual_url_variants;
    my @expected_url_variants;

    # Undefined URL
    eval { MediaWords::Util::URL::all_url_variants( $db, undef ); };
    ok( $@, 'Undefined URL' );

    # Non-HTTP(S) URL
    Readonly my $gopher_url => 'gopher://gopher.floodgap.com/0/v2/vstat';
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $gopher_url );
    @expected_url_variants = ( $gopher_url );
    is_deeply( [ sort @actual_url_variants ], [ sort @expected_url_variants ], 'Non-HTTP(S) URL' );

    # Basic test
    Readonly my $TEST_HTTP_SERVER_URL       => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    Readonly my $starting_url_without_cruft => $TEST_HTTP_SERVER_URL . '/first';
    Readonly my $cruft                      => '?utm_source=A&utm_medium=B&utm_campaign=C';
    Readonly my $starting_url               => $starting_url_without_cruft . $cruft;

    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third' . $cruft . '" />',
        '/third'  => 'This is where the redirect chain should end.',
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url, $starting_url_without_cruft,
        $TEST_HTTP_SERVER_URL . '/third',
        $TEST_HTTP_SERVER_URL . '/third' . $cruft
    );
    is_deeply( [ sort @actual_url_variants ], [ sort @expected_url_variants ], 'Basic all_url_variants() test' );

    # <link rel="canonical" />
    $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third' . $cruft . '" />',
        '/third'  => '<link rel="canonical" href="' . $TEST_HTTP_SERVER_URL . '/fourth" />',
    };

    $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url, $starting_url_without_cruft,
        $TEST_HTTP_SERVER_URL . '/third',
        $TEST_HTTP_SERVER_URL . '/third' . $cruft,
        $TEST_HTTP_SERVER_URL . '/fourth',
    );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        '<link rel="canonical" /> all_url_variants() test'
    );

    # Redirect to a homepage
    $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/',
    };

    $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url_without_cruft, $starting_url,
        $TEST_HTTP_SERVER_URL . '/second',
        $TEST_HTTP_SERVER_URL . '/second' . $cruft
    );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        '"Redirect to homepage" all_url_variants() test'
    );
}

sub test_all_url_variants_invalid_variants($)
{
    my ( $db ) = @_;

    my @actual_url_variants;
    my @expected_url_variants;

    # Invalid URL variant (suspended Twitter account)
    Readonly my $invalid_url_variant => 'https://twitter.com/Todd__Kincannon/status/518499096974614529';
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $invalid_url_variant );
    @expected_url_variants = ( $invalid_url_variant );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        'Invalid URL variant (suspended Twitter account)'
    );
}

sub test_get_topic_url_variants
{
    my ( $db ) = @_;

    my $data = {
        A => {
            B => [ 1, 2, 3 ],
            C => [ 4, 5, 6 ]
        },
        D => { E => [ 7, 8, 9 ] }
    };

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $data );

    my $story_1 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 1 };
    my $story_2 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 2 };
    my $story_3 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 3 };

    $db->query( <<END, $story_2->{ stories_id }, $story_1->{ stories_id } );
insert into topic_merged_stories_map ( source_stories_id, target_stories_id ) values( ?, ? )
END
    $db->query( <<END, $story_3->{ stories_id }, $story_2->{ stories_id } );
insert into topic_merged_stories_map ( source_stories_id, target_stories_id ) values( ?, ? )
END

    my $tag_set = $db->create( 'tag_sets', { name => 'foo' } );

    my $topic = {
        name              => 'foo',
        pattern           => 'foo',
        solr_seed_query   => 'foo',
        description       => 'foo',
        topic_tag_sets_id => $tag_set->{ tag_sets_id }
    };
    $topic = $db->create( 'topics', $topic );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_1->{ stories_id }
        }
    );

    $db->create(
        'topic_links',
        {
            topics_id    => $topic->{ topics_id },
            stories_id   => $story_1->{ stories_id },
            url          => $story_1->{ url },
            redirect_url => $story_1->{ url } . "/redirect_url"
        }
    );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_2->{ stories_id }
        }
    );

    $db->create(
        'topic_links',
        {
            topics_id    => $topic->{ topics_id },
            stories_id   => $story_2->{ stories_id },
            url          => $story_2->{ url },
            redirect_url => $story_2->{ url } . "/redirect_url"
        }
    );

    $db->create(
        'topic_stories',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_3->{ stories_id }
        }
    );

    $db->create(
        'topic_links',
        {
            topics_id  => $topic->{ topics_id },
            stories_id => $story_3->{ stories_id },
            url        => $story_3->{ url } . '/alternate',
        }
    );

    my $expected_urls = [
        $story_1->{ url },
        $story_2->{ url },
        $story_1->{ url } . "/redirect_url",
        $story_2->{ url } . "/redirect_url",
        $story_3->{ url },
        $story_3->{ url } . "/alternate"
    ];

    my $url_variants = MediaWords::Util::URL::get_topic_url_variants( $db, $story_1->{ url } );

    $url_variants  = [ sort { $a cmp $b } @{ $url_variants } ];
    $expected_urls = [ sort { $a cmp $b } @{ $expected_urls } ];

    is( scalar( @{ $url_variants } ), scalar( @{ $expected_urls } ), 'test_get_topic_url_variants: same number variants' );

    for ( my $i = 0 ; $i < @{ $expected_urls } ; $i++ )
    {
        is( $url_variants->[ $i ], $expected_urls->[ $i ], 'test_get_topic_url_variants: url variant match $i' );
    }
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_is_homepage_url();
    test_is_shortened_url();
    test_normalize_url();
    test_normalize_url_lossy();
    test_get_url_host();
    test_get_url_distinctive_domain();
    test_meta_refresh_url_from_html();
    test_link_canonical_url_from_html();
    test_url_and_data_after_redirects_nonexistent();
    test_url_and_data_after_redirects_http();
    test_url_and_data_after_redirects_html();
    test_url_and_data_after_redirects_http_loop();
    test_url_and_data_after_redirects_html_loop();
    test_url_and_data_after_redirects_cookies();
    test_http_urls_in_string();

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_all_url_variants( $db );
        }
    );

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_all_url_variants_invalid_variants( $db );
        }
    );

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_get_topic_url_variants( $db );
        }
    );

}

main();
