#!/usr/bin/perl
use strict;
use warnings;

my $tags = {
    "ascii" => 1,
    "usmil" => 0,
    "hex"   => 1,
    "test"  => 1,
};

my $data = [(0x55,0xaa) x (256*4)]; # cross-hatch pattern for undefined chars
my $tag;
my $labels;
my $y;
my $char_name = [map {sprintf "%02x", $_} (0..255)];

while(<>) {
    chomp;
    if (m{^\+(\w+)}) {
        $tag = $1;
        next;
    }
    if (m{^//}) {
        $labels = $_;
        $y = 0;
        next;
    }

    if (m{^$}) {
        next;
    }

    my $line = $_;
    my $pos = 0;

    while(1) {
        if ($line =~ m{^( *)([.X]{8})(.*)}) {
            my $pre = length $1;
            my $pic = $2;
            $line = $3;
            $pos += $pre;

            if ($pos >= length $labels) {
                last;
            }
            my $label = substr($labels, $pos);
            $pos += length $pic;

            my $char;
            my $name;
            if ($label =~ m{^//(([0-9a-f][0-9a-f]).{0,4})}) {
                $char = hex $2;
                $name = $1;
            } else {
                last;
            }

            my $byte = 0;
            for my $i (0..7) {
                $byte <<= 1;
                if (substr($pic, $i, 1) eq 'X') {
                    $byte |= 1;
                }
            }
            if (defined $tags->{$tag} && $tags->{$tag}) {
                $data->[$char * 8 + $y] = $byte;
                $char_name->[$char] = $name;
            }
        }
        else {
            last;
        }
    }

    $y++;
}

my $addr=0;
foreach my $byte (@$data) {
    if (($addr & 7) == 0) {
        printf("//%s\n", $char_name->[$addr/8]);
    }
    my $bits = sprintf("%08b", $byte);
    (my $pic = $bits) =~ tr/01/ X/;
    printf("%s    // %s\n", $bits, $pic);
    ++$addr;
    print "\n" if ($addr & 7) == 0;
}
