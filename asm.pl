#!/usr/bin/env perl
use strict;
use warnings;

my $default_outfile = "out/mem.bin";

sub usage {
    print "Usage: $0 [FILE ...]\n";
    print "Assemble files, and write a memory image to $default_outfile.0, $default_outfile.1\n";
    print "\n";
    print "OPTIONS\n";
    print "  -h, --help  display this message\n";
    print "  -o FILE     write image to FILE.0 and FILE.1\n";
    print "  -- FILE(s)  take all remaining arguments as files\n";
    exit 0
}

my $files = [];
my $outfile = $default_outfile;

while(my $arg = shift) {
    if ($arg =~ m/^--$/) {
        last;
    }
    elsif ($arg =~ m/^(-h|--help)$/) {
        usage();
    }
    elsif ($arg =~ m/^-o$/ && $#ARGV >= 0) {
        $outfile = shift;
    }
    elsif ($arg =~ m/^-/) {
        die "unknown option: $arg";
    }
    else {
        push @$files, $arg;
    }
}

push @$files, @ARGV;
die "no input files" if scalar @$files == 0;

our $image = [(0xff) x 65536];

# Syntax:
#     org expr
#     def label, expr
#     db expr
#     dw expr
#     ds "string"
#     align
#     alias rN name
#     .label
#     ; comment

# Expressions in order of precedence:
#   e := (e)
#   e := -e
#   e :- ~e
#   e := e1 * e2  ; e := e1 / e2 ; e := e1 % e2
#   e := e1 + e2  ; e := e1 - e2
#   e := e1 << e2 ; e := e1 >> e2
#   e := e1 ^ e2
#   e := e1 & e2
#   e := e2 | e2
#
#   hi(e1) lo(e1)           funcs
#   [0-9]+                  decimal
#   0x[0-9a-f]+             hex
#   0b[01]+                 binary
#   .[A-Za-z][A-Za-z0-9_]*  label
#
#   numeric constants may contain _ as digit separators

# modes:
#   0 = none
#   1 = reg1
#   2 = reg1, reg2
#   # = reg1, #num
#   b = reg1, bit num
#   [ = reg1, [reg2, #num] | reg1, [reg2]
#
# template bits:
#   rrrr : insert reg1
#   ssss : insert reg2
#   nnnn : insert num (bit width must be ok)
#   bbbb : insert log2(num)
#   ++++ : insert num as two's complement
#   ---- : insert -num as two's complement
#   oooo : insert offset as signed word count
#   mmmm : insert num or num>>8, with top bit indicating which

our $ops = {
    'mov:2'  => '0000:0000:ssss:rrrr',
    'mvn:2'  => '0000:0001:ssss:rrrr',
    'adc:2'  => '0000:0010:ssss:rrrr',
    'sbc:2'  => '0000:0011:ssss:rrrr',
    'add:2'  => '0000:0100:ssss:rrrr',
    'sub:2'  => '0000:0101:ssss:rrrr',
    'rsc:2'  => '0000:0110:ssss:rrrr',
    'rsb:2'  => '0000:0111:ssss:rrrr',
    '__0:_'  => '0000:1000:____:____', #
    '__1:_'  => '0000:1001:____:____', # \ 1024 encodings
    '__2:_'  => '0000:1010:____:____', # /
    '__3:_'  => '0000:1011:____:____', #
    'and:2'  => '0000:1100:ssss:rrrr',
    'cmp:2'  => '0000:1101:ssss:rrrr',
    'cmn:2'  => '0000:1110:ssss:rrrr',
    '__4:_'  => '0000:1111:____:____', # 256 encodings

    'ror:2'  => '0001:0000:ssss:rrrr',
    'lsl:2'  => '0001:0001:ssss:rrrr',
    'lsr:2'  => '0001:0010:ssss:rrrr',
    'asr:2'  => '0001:0011:ssss:rrrr',
    'orr:2'  => '0001:0100:ssss:rrrr',
    'eor:2'  => '0001:0101:ssss:rrrr',
    'bic:2'  => '0001:0110:ssss:rrrr',
    'tst:2'  => '0001:0111:ssss:rrrr',
    'ror:#'  => '0001:1000:nnnn:rrrr', 'rrx:0'  => '0001:1000:0000:rrrr',
    'lsl:#'  => '0001:1001:nnnn:rrrr',
    'lsr:#'  => '0001:1010:nnnn:rrrr',
    'asr:#'  => '0001:1011:nnnn:rrrr',
    'orr:#'  => '0001:1100:bbbb:rrrr',
    'eor:#'  => '0001:1101:bbbb:rrrr',
    'bic:#'  => '0001:1110:bbbb:rrrr',
    'tst:#'  => '0001:1111:bbbb:rrrr',

    'add:#'  => '001+:++++:++++:rrrr',  # TODO - should reject r15
    'sub:#'  => '001-:----:----:rrrr',  # TODO - should reject r15

    'ldb:['  => '010n:nnnn:ssss:rrrr',
    'ldw:['  => '011n:nnnn:ssss:rrrr',

    'stb:['  => '100n:nnnn:ssss:rrrr',
    'stw:['  => '101n:nnnn:ssss:rrrr',

    'mov:#'  => '110m:mmmm:mmmm:rrrr',

    'rdf:1'   => '0011:0000:rrrr:1111',
    'wrf:1'   => '0011:0001:rrrr:1111',

    'preq:0'  => '0011:1111:0000:1111',
    'prne:0'  => '0011:1111:0001:1111',
    'prcs:0'  => '0011:1111:0010:1111',
    'prhs:0'  => '0011:1111:0010:1111',
    'prcc:0'  => '0011:1111:0011:1111',
    'prlo:0'  => '0011:1111:0011:1111',
    'prmi:0'  => '0011:1111:0100:1111',
    'prpl:0'  => '0011:1111:0101:1111',
    'prvs:0'  => '0011:1111:0110:1111',
    'prvc:0'  => '0011:1111:0111:1111',
    'prhi:0'  => '0011:1111:1000:1111',
    'prls:0'  => '0011:1111:1001:1111',
    'prge:0'  => '0011:1111:1010:1111',
    'prlt:0'  => '0011:1111:1011:1111',
    'prgt:0'  => '0011:1111:1100:1111',
    'prle:0'  => '0011:1111:1101:1111',
    'nop:0'   => '0011:1111:1110:1111',
    'hlt:0'   => '0011:1111:1111:1111',

    'b:.'    => '1110:oooo:oooo:oooo',
    'br:.'   => '1110:oooo:oooo:oooo',
    'bra:.'  => '1110:oooo:oooo:oooo',
    'bl:.'   => '1111:oooo:oooo:oooo',
};

# [arity, map[op -> sub]]
our $eval_ops = [
    [ 2, { "|"  => sub {$_[0] |  $_[1]} }],
    [ 2, { "^"  => sub {$_[0] ^  $_[1]} }],
    [ 2, { "&"  => sub {$_[0] &  $_[1]} }],
    [ 2, { "<<" => sub {$_[0] << $_[1]},
           ">>" => sub {$_[0] >> $_[1]} }],
    [ 1, { "bit"=> sub {1 << $_[0]},
           "hi" => sub {$_[0] & 0xff00},
           "lo" => sub {$_[0] & 0x00ff} }],
    [ 2, { "+"  => sub {$_[0] +  $_[1]},
           "-"  => sub {$_[0] -  $_[1]} }],
    [ 2, { "*"  => sub {$_[0] *  $_[1]},
           "/"  => sub {$_[0] /  $_[1]},
           "%"  => sub {$_[0] %  $_[1]} }],
    [ 1, { "~"  => sub {~$_[0]},
           "-"  => sub {-$_[0]} }],
];

# func -> arity -> sub
our $funcs = {
    # "func_name" => { 1 => sub { some_func_of($_[0]) } },
    # ...
};

# At each step of evaluation, values are &ed with this mask.
our $value_mask = 0xffff_ffff;

my $lines = [];

while(my $file = shift @$files) {
    open my $fh, "<", $file or die "$file: $!";
    while (<$fh>) {
        chomp;
        s/^\s+//;       # remove leading space
        s/;.*//;        # remove comment - TODO will break in the presence of quoted ;
        s/\s+$//;       # remove trailing spaces
        push @$lines, [$file, $., $_];
    }
    $fh->close;
}

our $labels = {};
our $registers = { map {("r$_" => $_)} (0..15) };

foreach our $pass (1, 2) {
    our $org = 0x0000;
    foreach my $raw_line (@$lines) {
        our ($file, $lineno, $line) = @$raw_line;
        if ($line =~ s{^\.([a-z_]\w*)\s*}{}xi) {
            my $label = $1;
            if ($pass == 1) {
                if (exists $labels->{$label}) {
                    abort("symbol exists: %s", $label);
                }
                $labels->{$label} = $org;
            }
            else {
                print ".$label\n";
            }
        }

        next if $line eq '';

        if ($line =~ m{^def\s+(\w+)\s+(.*)\s*$}xi) {
            my $label = $1;
            my $expr = $2;
            if ($pass == 1) {
                if (exists $labels->{$label}) {
                    abort("symbol exists: %s", $label);
                }
            }
            $labels->{$label} = value($expr);
        }
        elsif ($line =~ m{^org\s+(.*?)$}xi) {
            $org = value($1);
        }
        elsif ($line =~ m{^db\s+(.*?)$}xi) {
            emit_byte(value($1));
        }
        elsif ($line =~ m{^dw\s+(.*?)$}xi) {
            emit_word(value($1));
        }
        elsif ($line =~ m{^ds\s+(.*?)$}xi) {
            emit_string($1);
        }
        elsif ($line =~ m{^align$}xi) {
            align();
        }
        elsif ($line =~ m{^alias\s+r([0-9]+)\s+([a-z_]\w*)$}xi) {
            alias($1, $2);
        }
        elsif ($line =~ m{^(\w+)\s*(.*?)\s*$}xi) {
            decode_op($1, $2);
        }
        else {
            abort("syntax error");
        }
    }
}

print ";; \n";
print ";; Writing image to $outfile.0, $outfile.1\n";
print ";; \n";
open my $fh0, ">:raw", "$outfile.0" or die "$outfile.0: $!";
open my $fh1, ">:raw", "$outfile.1" or die "$outfile.1: $!";
foreach my $i (0..32767) {
    my $hi = $image->[$i*2];
    my $lo = $image->[$i*2+1];
    $fh0->printf("%02x\n", $hi);
    $fh1->printf("%02x\n", $lo);
}
$fh1->close;
$fh0->close;
exit 0;

sub decode_op {
    my $op = shift;
    my $args = shift;

    my $mode = "0";
    my $desc = "implied";
    my $reg1 = "?";
    my $reg2 = "?";
    my $num = "?";

    if ($args =~ s{^([a-z_]\w*)\s*}{}xi && is_reg($1)) {
        $mode = '1';
        $desc = 'reg';
        $reg1 = get_reg($1);
        if ($args =~ s{^,\s*}{}xi) {
            if ($args =~ s{^([a-z_]\w*)\s*$}{}xi && is_reg($1)) {
                $mode = '2';
                $desc = 'reg1, reg2';
                $reg2 = get_reg($1);
            }
            elsif ($args =~ s{^\[\s*([a-z_]\w*)\s*\]\s*$}{}xi && is_reg($1)) {
                $mode = '[';
                $desc = 'reg1, [reg2]';
                $reg2 = get_reg($1);
                $num = 0;
            }
            elsif ($args =~ s{^\[\s*([a-z_]\w*)\s*,\s*(.*?)\s*\]\s*$}{}xi && is_reg($1)) {
                $mode = '[';
                $desc = 'reg1, [reg2, imm]';
                $reg2 = get_reg($1);
                $num = value($2);
            }
            elsif ($args =~ s{^(.*?)\s*$}{}xi) {
                $mode = '#';
                $desc = 'reg, imm';
                $num = value($1);
            }
        }
    }
    elsif ($args =~ s{^(\.\w+)$}{}xi) {
        $mode = '.';
        $desc = 'label';
        $num = value($1);
    }

    if ($args ne '') {
        abort("syntax error");
    }

    if ($::pass == 1) {
        $::org += 2;
        return;
    }

    my $op_mode = "$op:$mode";

    if (!defined $::ops->{$op_mode}) {
        abort("no such instruction format");
    }

    my $template = $::ops->{$op_mode};
    $template =~ s/://g;

    my $word = 0;
    my $bits;
    while($template ne '') {
        if ($template =~ s/^([01]+)//) {
            $bits = length $1;
            $word <<= $bits;
            $word |= oct "0b$1";
        }
        elsif ($template =~ s/^(r+)//) {
            $bits = length $1;
            my $min = 0;
            my $max = (1 << $bits)-1;
            if ($reg1 < $min || $reg1 > $max) {
                abort("bad register 'r%d'", $reg1);
            }
            $word <<= $bits;
            $word |= $reg1;
        }
        elsif ($template =~ s/^(s+)//) {
            $bits = length $1;
            my $min = 0;
            my $max = (1 << $bits)-1;
            if ($reg2 < $min || $reg2 > $max) {
                abort("bad register 'r%d'", $reg2);
            }
            $word <<= $bits;
            $word |= $reg2;
        }
        elsif ($template =~ s/^(n+)//) {
            $bits = length $1;
            my $max = (1 << $bits)-1;
            if ($num < 0) {
                abort("number is negative");
            }
            elsif ($num > $max) {
                abort("number exceeds 0x%x=%d", $max, $max);
            }
            $word <<= $bits;
            $word |= $num;
        }
        elsif ($template =~ s/^(m+)//) {
            $bits = length $1;
            my $mask_lo = (1 << $bits-1) - 1;
            my $mask_hi = $mask_lo << $bits-1;
            if (($num & $mask_lo) == $num) {
            }
            elsif (($num & $mask_hi) == $num) {
                $num >>= $bits-1;
                $num |= 1 << $bits-1;
            }
            else {
                abort("number does not match mask 0x%x or 0x%x", $mask_lo, $mask_hi);
            }
            $word <<= $bits;
            $word |= $num;
        }
        elsif ($template =~ s/^([-+]+)//) {
            $bits = length $1;
            if (substr($1, 0, 1) eq '-') {
                $num = -$num;
            }
            my $min = -(1 << $bits-1);
            my $max = (1 << $bits-1) - 1;
            if ($num < $min || $num > $max) {
                abort("number too wide for %d bits", $bits);
            }
            $word <<= $bits;
            $word |= $num & ((1 << $bits)-1);
        }
        elsif ($template =~ s/^(b+)//) {
            $bits = length $1;
            my $max = (1 << $bits)-1;
            my $bp = bitpos($num);
            if ($bp < 0) {
                abort("bit must be positive");
            }
            if ($bp > $max) {
                abort("bit exceeds %d", $max);
            }
            $word <<= $bits;
            $word |= $bp;
        }
        elsif ($template =~ s/^(o+)//) {
            $bits = length $1;
            if ($num & 1) {
                abort("branch target 0x%x not on word boundary", $num);
            }
            my $min = -(1 << $bits-1);
            my $max = (1 << $bits-1)-1;
            my $off = ($num - ($::org+2)) / 2;
            if ($off < $min || $off > $max) {
                abort("branch too far: %d words", $off);
            }
            $word <<= $bits;
            $word |= $off & ((1<<$bits)-1);
        }
        else {
            abort("(wtf) unexpected character '%s' in template", substr($template, 0, 1));
        }
    }

    emit_op($word);
}

sub is_reg {
    my $word = shift;
    return defined $::registers->{$word};
}

sub get_reg {
    my $word = shift;
    return $::registers->{$word};
}

sub bitpos {
    my $n = shift;
    my $bp = 0;
    while($n != 0 && !($n & 1)) {
        $bp++;
        $n >>= 1;
    }
    if ($n != 1) {
        abort("exactly 1 bit must be set: 0x%x / %d", $n, $n);
    }
    return $bp;
}

sub emit_byte {
    my $byte = shift;
    if ($::pass == 2) {
        printf("%04x %02x ; %s\n", $::org, $byte & 0xff, $::line);
        $::image->[$::org] = $byte & 0xff;
    }
    $::org += 1;
}

sub emit_word {
    my $word = shift;
    if ($::pass == 2) {
        printf("%04x %04x ; %s\n", $::org, $word & 0xffff, $::line);
        $::image->[$::org]   = $word >> 8;
        $::image->[$::org+1] = $word & 0xff;
    }
    $::org += 2;
}

sub emit_string {
    my $arg = shift;
    if ($arg =~ m{"(.*)"}) {
        my @chars = split //, $1;
        if ($::pass == 2) {
            for my $i (0..$#chars) {
                my $byte = ord($chars[$i]) & 0xff;
                if ($i == 0) {
                    printf("%04x %02x ; %s\n", $::org, $byte, $::line);
                } else {
                    printf("%04x %02x\n", $::org, $byte);
                }
                $::image->[$::org] = $byte;
                $::org += 1;
            }
        }
        else {
            $::org += scalar @chars;
        }
    }
    else {
        abort("expected quoted string");
    }
}

sub align {
    emit_byte(0x00) if $::org & 1;
}

sub alias {
    my $reg = shift;
    my $name = shift;
    $::registers->{$name} = $reg;
}

sub emit_op {
    my $op = shift;
    if ($::org & 1) {
        abort("instruction not on word boundary: org 0x%x", $::org);
    }
    emit_word($op);
}

sub value {
    my $e = shift;
    my ($v, $rest) = op_value($e, 0);
    if ($rest ne '') {
        abort("unexpected trailing '$rest'");
    }
    return $v;
}

sub op_value {
    my ($e, $level) = @_;

    if (!defined $::eval_ops->[$level]) {
        return bracket_value($e);
    }

    my $entry = $::eval_ops->[$level];
    my $arity = $entry->[0];

    if ($arity == 1) {
        my $infos = $entry->[1];
        my @sub_stack = ();
        UNARY_LOOP:
        while(1) {
            foreach my $op (keys %$infos) {
                my $sub = $infos->{$op};
                if($e =~ m{^ \Q$op\E \s*(.*) }x) {
                    $e = $1;
                    push @sub_stack, $sub;
                    next UNARY_LOOP;
                }
            }
            last;
        }

        my ($v, $rest) = op_value($e, $level+1);
        while(my $sub = pop @sub_stack) {
            $v = $sub->($v) & $::value_mask;
        }
        return ($v, $rest);
    }
    elsif ($arity == 2) {
        my ($v, $rest) = op_value($e, $level+1);

        my $infos = $entry->[1];
        BINARY_LOOP:
        while (1) {
            foreach my $op (keys %$infos) {
                my $sub = $infos->{$op};
                if ($rest =~ m{^ \Q$op\E \s*(.*) }x) {
                    (my $v2, $rest) = op_value($1, $level+1);
                    $v = $sub->($v, $v2) & $::value_mask;
                    next BINARY_LOOP;
                }
            }
            return ($v, $rest);
        }
    }
    else {
        die "unknown arity: $arity";
    }
}

sub bracket_value {
    my $e = shift;
    if ($e =~ m{^ \( \s*(.*) }x) {
        my ($v, $rest) = op_value($1, 0);
        if ($rest =~ m{^ \) \s*(.*) }x) {
            return ($v, $1);
        }
        abort("unbalanced parentheses");
    }
    my ($v, $rest) = func_value($e);
    return ($v, $rest);
}

sub func_value {
    my $e = shift;
    if ($e =~ m{^ (\w+)\( \s*(.*) }x) {
        my $func = $1;
        my $rest = $2;
        if (!defined $::funcs->{$func}) {
            abort("unknown func: %s", $func);
        }
        my $info = $funcs->{$func};
        my $v;
        my @args = ();
        if ($rest =~ m{^ \) \s*(.*) }x) {
            $rest = $1;
        }
        else {
            while(1) {
                ($v, $rest) = op_value($rest, 0);
                push @args, $v;
                if ($rest =~ m{^ , \s*(.*) }x) {
                    $rest = $1;
                }
                elsif ($rest =~ m{^ \) \s*(.*) }x) {
                    $rest = $1;
                    last;
                }
                else {
                    abort("unbalanced parentheses");
                }
            }
        }

        my $arity = scalar @args;
        if (!defined $info->{$arity}) {
            abort("func '%s' does not take %d arguments", $func, $arity);
        }
        my $sub = $info->{$arity};
        $v = $sub->(@args) & $::value_mask;
        return ($v, $rest);
    }
    my ($v, $rest) = terminal_value($e);
    return ($v, $rest);
}

#   [0-9]+(_[0-9]+)*
#   0x[0-9a-f]+(_[0-9a-f]+)*
#   0b[01]+(_[01]+)*
sub terminal_value {
    my $e = shift;
    my ($v, $rest);
    if ($e =~ m{^ 0x( [0-9a-f]+ (?:[0-9a-f_]+)* ) \s*(.*)}xi) {
        (my $digits, $rest) = ($1, $2);
        $digits =~ s/_//;
        $v = hex($digits);
    }
    elsif ($e =~ m{^ 0b( [01]+ (?:[01_]+)* ) \s*(.*)}xi) {
        (my $digits, $rest) = ($1, $2);
        $digits =~ s/_//;
        $v = oct("0b$digits");
    }
    elsif ($e =~ m{^ ( [0-9]+ (?:[0-9_]+)* ) \s*(.*)}xi) {
        (my $digits, $rest) = ($1, $2);
        $digits =~ s/_//;
        $v = 0+$digits;
    }
    elsif ($e =~ m{^ \.([a-z_]\w*) \s*(.*)}xi) {
        if (defined $::labels->{$1}) {
            ($v, $rest) = ($::labels->{$1}, $2);
        }
        elsif ($::pass == 1) {
            ($v, $rest) = (0, $2);
        }
        else {
            abort("undefined symbol: %s", $1);
        }
    }
    else {
        abort("cannot evaluate: %s", $e);
    }
    return ($v & $::value_mask, $rest);
}

sub abort {
    my $fmt = shift;
    my @args = @_;
    printf("%s:%d: %s -- %s\n", $::file, $::lineno, $::line, sprintf($fmt, @args));
    exit 1;
}
