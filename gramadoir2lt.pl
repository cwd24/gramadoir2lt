#!/usr/bin/perl

use strict;
use warnings;

# http://borel.slu.edu/gramadoir/manual/x596.html#CHUNKS
# http://wiki.languagetool.org/developing-a-disambiguator
# https://borel.slu.edu/gramadoir/manual/index.html

use utf8;
use open qw/:std :utf8/;

use Encode;
use XML::LibXML qw/:libxml/;
use Lingua::GA::Gramadoir::Languages;


my $parser = XML::LibXML->new();

my %enc = (
	af	=>	"iso-8859-1",
	ak	=>	"utf8",
	cy	=>	"iso-8859-14",
	eo	=>	"iso-8859-3",
	fr	=>	"iso-8859-1",
	ga	=>	"iso-8859-1",
	gd	=>	"iso-8859-1",
	hil	=>	"iso-8859-1",
	ig	=>	"utf8",
	is	=>	"iso-8859-1",
	kw	=>	"iso-8859-1",
	lnc	=>	"iso-8859-1",
	tl	=>	"iso-8859-1",
	wa	=>	"iso-8859-1",
);
my %files = (
	aonchiall => 'disambiguation',
	rialacha => 'rules'
);
my %no_rule = (
	ANAITHNID => 1,
	ANKOTHVOS => 1,
	UNKNOWN => 1,
	NEAMHCHOIT => 1,
	NAMMENOWGH => 1,
	UNCOMMON => 1,
);

open (my $fh, "<:encoding(iso-8859-1)", 'gramadoir/engine/messages.txt');
my %errors = map { $_ =>{} } keys %enc;
my %po = map { $_ => Lingua::GA::Gramadoir::Languages->get_handle($_, 'en-US') }
	keys %enc;
while (my $line = <$fh>) {
        next if $line =~ /^#/;
        chomp $line;
        next unless $line =~ /^(\S+)\s+'(.*)'$/;
        my ($keys,$value) = ($1,$2);
	$value =~ s!\\/\\1\\/!/[_1]/!;
	$value =~ s!\\([/'])!$1!g;
	while (my ($lang, $po) = each %po) {
		eval {
			$value = $po->maketext($value,'<suggestion>%s</suggestion>');
		};
		if ($@) {
			$value =~ s!\\/\\1\\/!<suggestion>%s</suggestion>!;
		}
        	foreach my $key (split '=', $keys) {
			$errors{$lang}->{$key} = $value;
		}
	}
}
close ($fh);

foreach my $lang (keys %enc) {
	foreach my $file (keys %files) {
		open ($fh, "<:encoding($enc{$lang})", "gramadoir/$lang/$file-$lang.in");
	
		my $doc = XML::LibXML::Document->new('1.0','UTF-8');
		my $rules = $doc->createElement('rules');
		$doc->setDocumentElement($rules);
		while (my $line = <$fh>) {
			next if $line =~ /^\s*$/;
			chomp $line;
			if ( $line =~/^#/ ) {
				my $c = $doc->createComment($line);
				$rules->appendChild($c);
				next;
			}
			my ($match,$replace) = split ':', $line;
			next if $no_rule{$replace};
			if ($replace eq 'OK' && $match =~ /\b(\w+) \1\b/) {
				next;
				#TODO add to list
			}
			my $rule = $doc->createElement('rule');
			$rules->appendChild($rule);
			gen_pattern($doc,$rule,$match,$replace eq 'OK');
			# should change this to work on different files
			if ($replace =~ /^!?</) {
				gen_disambig($doc,$rule,$replace)
			} elsif ($replace !~ /^OK\s*$/) {
				my $m = $doc->createElement('message');
				$replace =~ /^([A-Z]*)(\{(.*)\})?/;
				$m->appendWellBalancedChunk(
					exists $errors{$lang}->{$1} ?
					sprintf($errors{$lang}->{$1},($3?$3:()))
					: $1);
				$rule->appendChild($m);
			}
		}
		close ($fh);
		if ( $rules->findnodes('//rule') ) {
			mkdir $lang unless(-d $lang);
			$doc->toFile("$lang/$files{$file}.xml",1);
		}
	}
}

sub gen_pattern {
	my ($doc,$rule,$match,$pattern) = (shift,shift,shift,shift);
	$pattern = $doc->createElement($pattern?'antipattern':'pattern');
	$rule->appendChild($pattern);
	$match =~ s/\[^>\]/./g;
	my @tokens = split ' ', $match;
	while (@tokens) {
		my $token = shift @tokens;
		while ($token =~ /^<.*[^>]$/) {
			die $match unless @tokens;
			$token .= ' ' . shift(@tokens)
		}
		my $text;
		my $t = $doc->createElement('token');
		my $p = $pattern;
		if ($token =~ /^[^<]/) {
			$text = $token;
		}
		elsif ($token =~ /^<B/) {
			my $dom = $parser->parse_balanced_chunk($token);
			my $marker = $doc->createElement('marker');
			$p->appendChild($marker);
			$p = $marker;
			$text = $dom->lastChild->nodeValue;
			# TODO add postags under <Z>
		}
		elsif ($token =~ m!^<([^>]+)/?>((.+)</[^>]+>)?$!) {
			$t->setAttribute( 'postag', $1 );
			$text = $3;
		}
		else {
			die $token;
		}
		if ($text) {
			$text =~ s/\[(\w)\1\]/\l$1/ig;
			$text =~ s/^\s+//;
			$text =~ s/\s+$//;
			$t->appendText($text) unless $text eq 'ANYTHING';
		}
		$p->appendChild($t);
	}
}
sub gen_disambig {
	my ($doc,$rule,$replace) = (shift,shift,shift);
	my $disambig = $doc->createElement('disambig');
	$rule->appendChild($disambig);
	my $action = ($replace =~ s/^!//) ? 'remove' : 'filter';
	$disambig->setAttribute('action', $action);
	$replace =~ s!^<!!;
	$replace =~ s!/?>$!!;
	$replace =~ s!"!'!g;
	$disambig->setAttribute('postag', $replace);
}
