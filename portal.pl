#!/usr/bin/perl -w
use strict;
use warnings;
use LWP::UserAgent;
use POSIX 'strftime';
use URI;
use Email::Sender::Simple 'sendmail';
use Email::MIME;
use Encode;

package HTMLStrip;
use base "HTML::Parser";

my $is_contents;
my @attaches;
my $string;
my $tmp_in_a;
my $tmp_name;
my $tmp_url;

sub new {
    my $class = shift;
    my $self = HTML::Parser->new;
    $is_contents = 0;
    @attaches = ();
    $string = "";
    $tmp_in_a = 0;
    $tmp_name = "";
    $tmp_url = "";
    return bless $self, $class;
}

sub text {
    my ($self, $text) = @_;
    if ($is_contents) {
        $string .= $text;
    }
    if ($tmp_in_a) {
        $tmp_name .= $text;
    }
}

sub start {
    my ($self, $tag, $attr, $attrseq, $origtext) = @_;
    if ($tag eq 'pre') {
        $is_contents = 1;
    }
    if ($tag eq 'p') {
        $is_contents = 0;
    }
    if ($tag eq 'a') {
        if (!$is_contents) {
            if (!$tmp_in_a) {
                $tmp_in_a = 1;
                $tmp_name = "";
                $tmp_url = $attr->{href};
            }
        }
    }
}

sub end {
    my ($self, $tag, $origtext) = @_;
    if ($tag eq 'pre') {
        $is_contents = 0;
    }
    if ($tag eq 'a') {
        if ($tmp_in_a) {
            $tmp_in_a = 0;
            push @attaches, {name=>"$tmp_name", url=>$tmp_url};
        }
    }
}

package main;

my @tos = ('');    # email addresses to send new posts
my $record = '';   # path to local record of read posts.

if (!-e $record) {
	open RECORD, '>', $record or die "Cannot create file: $!";;
    print RECORD "0\n";
    close RECORD;
}

open INPUT, '<', $record or die "Cannot open input file: $!";
my $last_upd = <INPUT>;
chomp ($last_upd);

my $url = ''; # url
my $agent = LWP::UserAgent->new;
my $header_response = $agent->head( $url );
if ($header_response->is_error) {
    exit;
}
my $last_mod = $header_response->headers->last_modified;
if ($last_mod <= $last_upd) {
    close INPUT;
	exit;
}

my $content_response = $agent->get( $url );
if ($content_response->is_error) {
    exit;
}
my $content = $content_response->decoded_content;
my @local_posts   = ();
my @old_urls_date = ();
my $old_date = 0;
my @new_urls_date = ();
my @new_posts = ();
my $lookahead_url = "";
my $lookahead_date = 0;

while($content =~ /([^\n]+)\n?/g){
	if ($1 =~ /^\<TR\>.*\<A HREF=\"([^\"]*)\"\>(.*)\<\/A\>.*\<TD\>([^\<]*)\<\/TD\>\<TD\>(\d+)-(\d+)-(\d+)\<\/TD\>\<\/TR\>$/) {
		my $post_url = $1;
		my $post_title = $2;
        my $post_publisher = $3;
        my $post_date = $4 . $5 . $6;

        if ($old_date != $post_date) {
            $old_date = $post_date;
            @old_urls_date = ();
            @new_urls_date = ();
            if ($lookahead_date == 0 || $lookahead_date >= $old_date) {
                push @local_posts, "$lookahead_date $lookahead_url\n" if $lookahead_date >= $post_date;
                push @old_urls_date, $lookahead_url if $lookahead_date == $old_date;
                $lookahead_url = "";
                $lookahead_date = 0;
                while (<INPUT>) {
                    if ($_ =~ /^(\d+) (.+)$/) {
                        if ($1 < $old_date) {
                            $lookahead_date = $1;
                            $lookahead_url  = $2;
                            last;
                        }
                        elsif ($1 == $old_date) {
                            push @old_urls_date, $2;
                        }
                        push @local_posts, $_;
                    }
                }
            }
        }
        if (!&exists_in_list($post_url, @old_urls_date) && !&exists_in_list($post_url, @new_urls_date)) {
            push @new_urls_date, $post_url;
            push @local_posts, "$post_date $post_url\n";

            my $post_absurl = URI->new_abs($post_url, $url);
            my $post = HTMLStrip->new->parse($agent->get($post_absurl)->decoded_content);
            if (@attaches){
                $string .= decode('utf8', "\n\n\n（添付ファイル）\n");
                foreach (@attaches) {
                    my $name = $_->{name};
                    my $url = URI->new_abs($_->{url}, $url);
                    $string .= "$name\n  $url\n";
                }
            }
            $string .= "\n---\n$post_absurl\n";
            push @new_posts, {title=>$post_title, contents=>$string};
        }
	}
}
while (@new_posts) {
    my $post = pop @new_posts;
    my $email = Email::MIME->create(
        header => [
            From    => encode('MIME-Header-ISO_2022_JP' => ''), # from
            To      => encode('MIME-Header-ISO_2022_JP' => join(',', @tos)),
            Subject => encode('MIME-Header-ISO_2022_JP' => $post->{title}),
        ],
        attributes => {
            content_type => 'text/plain',
            charset      => 'ISO-2022-JP',
            encoding     => '7bit',
        },
        body => encode('iso-2022-jp' => $post->{contents}),
        );
    
    sendmail($email);
}
close INPUT;

open OUTPUT, '>', $record or die "Cannot open output file: $!";;
print OUTPUT "$last_mod\n";
print OUTPUT @local_posts;
close OUTPUT;

sub exists_in_list {
    my $string = shift @_;

    foreach (@_) {
        return 1 if $_ eq $string
    }

    return 0;
}
