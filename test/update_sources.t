#! /usr/bin/perl -w
use strict;
use warnings;
use DBI;
use Test::More 'no_plan';
use lib '../';
use util::Io;

do 'reset_db.pl';
my %cfg = do '../config.pl';
chdir('../');

my $dbh = DBI->connect('DBI:mysql:'.$cfg{'MYSQL_DB'}, $cfg{'MYSQL_USER'},
                       $cfg{'MYSQL_PASS'}, { RaiseError => 1 })
    or die DBI->errstr;

sub sql {
    my $sql = shift;
    system("echo \"$sql\" | /usr/bin/mysql -u$cfg{'MYSQL_USER'} "
           ."-p$cfg{'MYSQL_PASS'} $cfg{'MYSQL_DB'}");
}

system('./update_sources add s1');
my ($author, $crawl, $url) = $dbh->selectrow_array(
    "SELECT default_author, crawl_depth, url FROM sources WHERE url = 's1'");
is($url, 's1', 'add test url');
is($author, undef, 'default author NULL'); 
is($crawl, 1, 'default crawl 1'); 

system('./update_sources modify s1 --author "xyz"');
($author, $crawl) = $dbh->selectrow_array(
    "SELECT default_author, crawl_depth FROM sources WHERE url = 's1'");
is($author, 'xyz', 'modify author changes author record'); 
is($crawl, 1, 'modify author does not change crawl record'); 

my ($id) = $dbh->selectrow_array(
    "SELECT source_id FROM sources LIMIT 1");
system("./update_sources modify $id --crawl 2");
($author, $crawl) = $dbh->selectrow_array(
    "SELECT default_author, crawl_depth FROM sources WHERE url = 's1'");
is($author, 'xyz', 'modify crawl does not change author record'); 
is($crawl, 2, 'modify crawl via ID changes crawl record'); 

system('./update_sources modify s1 --author "" --crawl 3 --url "s2"');
($author, $crawl, $url) = $dbh->selectrow_array(
    "SELECT default_author, crawl_depth, url FROM sources WHERE url = 's2'");
is($url, 's2', 'can modify url'); 
ok(!defined($author), 'empty string resets default_author to NULL'); 
is($crawl, 3, 'can modify author, crawl and url together'); 

sql("INSERT INTO documents (title) VALUES ('d1')");
my ($doc_id) = $dbh->selectrow_array(
    "SELECT document_id FROM documents LIMIT 1");
sql("INSERT INTO locations (url, document_id) VALUES ('l1', $doc_id)");
($id) = $dbh->selectrow_array(
    "SELECT source_id FROM sources LIMIT 1");
my ($loc_id) = $dbh->selectrow_array(
    "SELECT location_id FROM locations LIMIT 1");
sql("INSERT INTO links (source_id, location_id) VALUES ($id, $loc_id)");
system('./update_sources delete s2');
($url) = $dbh->selectrow_array(
    "SELECT url FROM sources WHERE url = 's2'");
ok(!defined($url), 'can delete source'); 
($url) = $dbh->selectrow_array(
    "SELECT url FROM locations LIMIT 1");
ok(!defined($url), 'deleting source deletes associated location'); 
($url) = $dbh->selectrow_array(
    "SELECT source_id FROM links LIMIT 1");
ok(!defined($url), 'deleting source deletes associated link'); 
($url) = $dbh->selectrow_array(
    "SELECT document_id FROM documents LIMIT 1");
ok(!defined($url), 'deleting source deletes associated document'); 

sql("INSERT INTO sources (url) VALUES ('s1')");
sql("INSERT INTO sources (url) VALUES ('s2')");
sql("INSERT INTO locations (url) VALUES ('l1')");
($id) = $dbh->selectrow_array(
    "SELECT source_id FROM sources WHERE url = 's1'");
my ($id2) = $dbh->selectrow_array(
    "SELECT source_id FROM sources WHERE url = 's2'");
($loc_id) = $dbh->selectrow_array(
    "SELECT location_id FROM locations LIMIT 1");
sql("INSERT INTO links (source_id, location_id) VALUES ($id, $loc_id)");
sql("INSERT INTO links (source_id, location_id) VALUES ($id2, $loc_id)");
system('./update_sources delete s1');
($url) = $dbh->selectrow_array(
    "SELECT location_id FROM locations WHERE location_id = $loc_id LIMIT 1");
is($url, $loc_id, 'associated location not deleted when linked from elsewhere'); 
system('./update_sources delete s2');
($url) = $dbh->selectrow_array(
    "SELECT url FROM locations WHERE location_id = $loc_id LIMIT 1");
ok(!defined($url), 'associated location deleted when no longer linked'); 

sql("INSERT INTO documents (title) VALUES ('d1')");
sql("INSERT INTO documents (title) VALUES ('d2')");
($doc_id) = $dbh->selectrow_array(
    "SELECT document_id FROM documents WHERE title='d1'");
my ($doc_id2) = $dbh->selectrow_array(
    "SELECT document_id FROM documents WHERE title='d2'");
sql("INSERT INTO sources (url) VALUES ('s1')");
sql("INSERT INTO sources (url) VALUES ('s2')");
($id) = $dbh->selectrow_array(
    "SELECT source_id FROM sources WHERE url = 's1'");
($id2) = $dbh->selectrow_array(
    "SELECT source_id FROM sources WHERE url = 's2'");
sql("INSERT INTO locations (url,document_id) VALUES ('l1', $doc_id)");
sql("INSERT INTO locations (url,document_id) VALUES ('l2', $doc_id)");
sql("INSERT INTO locations (url,document_id) VALUES ('l3', $doc_id2)");
sql("INSERT INTO locations (url,document_id) VALUES ('l4', $doc_id2)");
($loc_id) = $dbh->selectrow_array(
    "SELECT location_id FROM locations WHERE url = 'l1'");
my ($loc_id2) = $dbh->selectrow_array(
    "SELECT location_id FROM locations WHERE url = 'l2'");
sql("INSERT INTO links (source_id, location_id) VALUES ($id, $loc_id)");
sql("INSERT INTO links (source_id, location_id) VALUES ($id2, $loc_id2)");
system('./update_sources delete s1');
($url) = $dbh->selectrow_array(
    "SELECT document_id FROM documents WHERE title = 'd1'");
ok(defined($url), 'associated document not deleted when also located elsewhere'); 
($url) = $dbh->selectrow_array(
    "SELECT location_id FROM locations WHERE location_id = $loc_id LIMIT 1");
ok(!defined($url), 'associated location of multi-located document deleted');
system('./update_sources delete s2');
($url) = $dbh->selectrow_array(
    "SELECT document_id FROM documents WHERE title = 'd1'");
ok(!defined($url), 'associated document deleted when no longer located elsewhere'); 

sql("INSERT INTO sources (url) VALUES ('s1')");
($id) = $dbh->selectrow_array(
    "SELECT source_id FROM sources WHERE url = 's1'");
sql("INSERT INTO sources (url, parent_id) VALUES ('s1c1', $id)");
($id2) = $dbh->selectrow_array(
    "SELECT source_id FROM sources WHERE url = 's1c1'");
sql("INSERT INTO sources (url, parent_id) VALUES ('s1c1c', $id2)");
sql("INSERT INTO sources (url, parent_id) VALUES ('s1c2', $id)");
system('./update_sources modify s1 --author=abc');
($author) = $dbh->selectrow_array(
    "SELECT default_author FROM sources WHERE url = 's1c2'");
is($author, 'abc', 'changing author propagates to child'); 
($author) = $dbh->selectrow_array(
    "SELECT default_author FROM sources WHERE url = 's1c1c'");
is($author, 'abc', 'changing author propagates to grandchild'); 
system('./update_sources delete s1');
($url) = $dbh->selectrow_array(
    "SELECT url FROM sources WHERE url = 's1c1c'");
ok(!defined($url), 'deleting source deletes grandchildren'); 

# For testing CGI, set the URL of update_sources:
my $UPDATE_URL = "http://localhost/opp-tools/update_sources";

sub read_url {
    my $url = shift;
    my $res = fetch_url($url);
    return $res->{content};
}

SKIP: {

    my $res = read_url("$UPDATE_URL?action=asdf");
    skip "CGI not properly configured (url: $UPDATE_URL)"
        unless $res && $res =~ /status:'0'/;

    like($res, qr/status:'0'/, "invalid CGI command yields status 0");

    $res = read_url("$UPDATE_URL?action=add&id=u1"); 
    like($res, qr/status:'1'/, "CGI add yields status 1");
    ($author, $crawl, $url) = $dbh->selectrow_array(
        "SELECT default_author, crawl_depth, url "
        ."FROM sources WHERE url = 'u1'");
    is($url, 'u1', 'add test url via CGI');
    is($author, undef, 'default author NULL when added via CGI');
    is($crawl, 1, 'default crawl 1 when added via CGI');

    $res = read_url("$UPDATE_URL?action=modify&id=u1&url=u2&author=xyz");
    ($author, $crawl, $url) = $dbh->selectrow_array(
        "SELECT default_author, crawl_depth, url "
        ."FROM sources WHERE url = 'u2'");
    is($url, 'u2', 'can change url via CGI');
    is($author, 'xyz', 'can set author via CGI');
    
}
