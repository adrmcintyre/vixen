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

our ($file, $lineno, $line);
our $image = [(0xff) x 65536];
our $labels = {};
our $last_label = undef;
our $scope = "";
our $scopes = [$scope];
our $registers = { map {("r$_" => $_)} (0..15) };
our $pass;
our $org;

# Syntax:
#   org expr        - set current memory position
#   def label expr  - define a constant, referenced as .label
#   db expr, ...    - insert 1 or more bytes
#   dw expr, ...    - insert 1 or more 16-bit words
#   dl expr, ...    - insert 1 or more 32-bit double words 
#   ds "string"     - insert a string (not \0 delimited)
#   align           - align current memory position to word boundary
#   alias rN name   - create a register alias
#   .label          - define a label referencing the current memory position
#   ; comment       - ignore comment
#   begin ... end   - delimit a scope for labels and register aliases
#   { ... }         - alternative scope syntax

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
#   'c'                     char
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

our $ops = {};

sub def_op {
    my $op = shift;
    my $info = shift;

    push @{$::ops->{$op}}, $info;
}

def_op('mov' => {mode => 2, pat => '0000:0000:ssss:rrrr'});
def_op('mvn' => {mode => 2, pat => '0000:0001:ssss:rrrr'});
def_op('adc' => {mode => 2, pat => '0000:0010:ssss:rrrr'});
def_op('sbc' => {mode => 2, pat => '0000:0011:ssss:rrrr'});
def_op('add' => {mode => 2, pat => '0000:0100:ssss:rrrr'});
def_op('sub' => {mode => 2, pat => '0000:0101:ssss:rrrr'});
def_op('rsc' => {mode => 2, pat => '0000:0110:ssss:rrrr'});
def_op('rsb' => {mode => 2, pat => '0000:0111:ssss:rrrr'});

def_op('clz' => {mode => 2, pat => '0000:1000:ssss:rrrr'});
# '0000:1001:____:____', # 256 encodings
def_op('mul' => {mode => '2', pat => '0000:1010:ssss:rrrr'});
def_op('muh' => {mode => '2', pat => '0000:1011:ssss:rrrr'});
def_op('and' => {mode => '2', pat => '0000:1100:ssss:rrrr'});
def_op('cmp' => {mode => '2', pat => '0000:1101:ssss:rrrr'});
def_op('cmn' => {mode => '2', pat => '0000:1110:ssss:rrrr'});
# '0000:1111:____:____', # 256 encodings

def_op('ror' => {mode => '2', pat => '0001:0000:ssss:rrrr'});
def_op('lsl' => {mode => '2', pat => '0001:0001:ssss:rrrr'});
def_op('asl' => {mode => '2', pat => '0001:0001:ssss:rrrr'});   # alias for lsl
def_op('lsr' => {mode => '2', pat => '0001:0010:ssss:rrrr'});
def_op('asr' => {mode => '2', pat => '0001:0011:ssss:rrrr'});
def_op('orr' => {mode => '2', pat => '0001:0100:ssss:rrrr'});
def_op('eor' => {mode => '2', pat => '0001:0101:ssss:rrrr'});
def_op('bic' => {mode => '2', pat => '0001:0110:ssss:rrrr'});
def_op('tst' => {mode => '2', pat => '0001:0111:ssss:rrrr'});

def_op('rrx' => {mode => '1', pat => '0001:1000:0000:rrrr'});

def_op('ror' => {mode => '#', pat => '0001:1000:nnnn:rrrr'});  # TODO - should reject n=0
def_op('lsl' => {mode => '#', pat => '0001:1001:nnnn:rrrr'});
def_op('asl' => {mode => '#', pat => '0001:1001:nnnn:rrrr'});   # alias for lsl
def_op('lsr' => {mode => '#', pat => '0001:1010:nnnn:rrrr'});
def_op('asr' => {mode => '#', pat => '0001:1011:nnnn:rrrr'});
def_op('orr' => {mode => '#', pat => '0001:1100:bbbb:rrrr'});
def_op('eor' => {mode => '#', pat => '0001:1101:bbbb:rrrr'});
def_op('bic' => {mode => '#', pat => '0001:1110:bbbb:rrrr'});
def_op('tst' => {mode => '#', pat => '0001:1111:bbbb:rrrr'});

def_op('add' => {mode => '#', pat => '001+:++++:++++:rrrr'});  # TODO - should reject r15
def_op('sub' => {mode => '#', pat => '001-:----:----:rrrr'});  # TODO - should reject r15

def_op('ldb' => {mode => '[', pat => '010n:nnnn:ssss:rrrr'});
def_op('ldw' => {mode => '[', pat => '011n:nnnn:ssss:rrrr'});

def_op('stb' => {mode => '[', pat => '100n:nnnn:ssss:rrrr'});
def_op('stw' => {mode => '[', pat => '101n:nnnn:ssss:rrrr'});

#def_op('ldi' => {mode => '#', special => \&ldi});  # TODO - pseudo-op
def_op('mov' => {mode => '#', pat => '110m:mmmm:mmmm:rrrr'});

def_op('swi' => {mode => '@', pat => '0010:nnnn:nnnn:1111'});
def_op('mrs' => {mode => '<', pat => '0011:0ss0:rrrr:1111'});
def_op('msr' => {mode => '>', pat => '0011:0ss1:rrrr:1111'});
def_op('rtu' => {mode => '1', pat => '0011:1000:rrrr:1111'});

def_op('preq' => {mode => '0', pat => '0011:1111:0000:1111'});
def_op('prne' => {mode => '0', pat => '0011:1111:0001:1111'});
def_op('prcs' => {mode => '0', pat => '0011:1111:0010:1111'});
def_op('prhs' => {mode => '0', pat => '0011:1111:0010:1111'});
def_op('prcc' => {mode => '0', pat => '0011:1111:0011:1111'});
def_op('prlo' => {mode => '0', pat => '0011:1111:0011:1111'});
def_op('prmi' => {mode => '0', pat => '0011:1111:0100:1111'});
def_op('prpl' => {mode => '0', pat => '0011:1111:0101:1111'});
def_op('prvs' => {mode => '0', pat => '0011:1111:0110:1111'});
def_op('prvc' => {mode => '0', pat => '0011:1111:0111:1111'});
def_op('prhi' => {mode => '0', pat => '0011:1111:1000:1111'});
def_op('prls' => {mode => '0', pat => '0011:1111:1001:1111'});
def_op('prge' => {mode => '0', pat => '0011:1111:1010:1111'});
def_op('prlt' => {mode => '0', pat => '0011:1111:1011:1111'});
def_op('prgt' => {mode => '0', pat => '0011:1111:1100:1111'});
def_op('prle' => {mode => '0', pat => '0011:1111:1101:1111'});
def_op('nop'  => {mode => '0', pat => '0011:1111:1110:1111'});
def_op('hlt'  => {mode => '0', pat => '0011:1111:1111:1111'});

def_op('b'   => {mode => '.', pat => '1110:oooo:oooo:oooo'});
def_op('br'  => {mode => '.', pat => '1110:oooo:oooo:oooo'});
def_op('bra' => {mode => '.', pat => '1110:oooo:oooo:oooo'});
def_op('bl'  => {mode => '.', pat => '1111:oooo:oooo:oooo'});

my $re_reg1 = qr{(?<reg1> [a-z_]\w*)}xi;
my $re_reg2 = qr{(?<reg2> [a-z_]\w*)}xi;
my $re_expr = qr{ (?<expr> .*?) }xi;
my $re_imm  = qr{ \# s* $re_expr }xi;
my $re_comma = qr{ \s* , \s* }xi;
my $re_special = qr{(?<special> flags|uflags|u13|u14)}xi;

our $mode_regex = {
    '0' => qr{ }xi,
    '1' => qr{ $re_reg1 }xi,
    '2' => qr{ $re_reg1 $re_comma $re_reg2 }xi,
    '[' => qr{ $re_reg1 $re_comma \[ $re_reg2 (?: $re_comma $re_imm )? \s* \] }xi,
    '@' => qr{ $re_imm }xi,
    '#' => qr{ $re_reg1 $re_comma $re_imm }xi,
    '.' => qr{ $re_expr }xi,
    '<' => qr{ $re_reg1 $re_comma $re_special }xi,
    '>' => qr{ $re_special $re_comma $re_reg1 }xi,
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

sub decode_op {
    my $op = shift;
    my $args = shift;

    my $template = undef;
    my $reg1 = undef;
    my $reg2 = undef;
    my $num = 0;
    my $special = undef;

    my $infos = $::ops->{$op};
    foreach my $info (@$infos) {
        my $mode = $info->{mode};
        my $re = $::mode_regex->{$mode};
        if ($args =~ m{^$re\s*$}) {
            my %match = %+;
            $template = $info->{pat};
            $reg1 = get_reg($match{reg1})   if defined $match{reg1};
            $reg2 = get_reg($match{reg2})   if defined $match{reg2};
            $reg2 = get_special($match{special}) if defined $match{special};
            $num  = get_value($match{expr}) if defined $match{expr};
            last;
        }
    }

    if (!defined $template) {
        abort("syntax error");
    }

    if ($::pass == 1) {
        $::org += 2;
        return;
    }

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

            # WHAT ABOUT PREDICATION....?
            # b far_address:
            # +00   ldw pc, [pc]
            # +02   dw far_address

            # bl far_address:
            # +00   mov link, pc
            # +02   add link, 6
            # +04   ldw pc, [pc]
            # +06   dw far_address
            # +08   ; resume

        }
        else {
            abort("(wtf) unexpected character '%s' in template", substr($template, 0, 1));
        }
    }

    emit_op($word);
}

sub get_reg {
    my $word = shift;
    foreach my $scope (@$::scopes) {
        if (defined $::registers->{$scope.$word}) {
            return $::registers->{$scope.$word};
        }
    }
    abort("unknown register: $word");
}

sub get_special {
    my $word = lc(shift);
    return 0 if $word eq 'flags';
    return 1 if $word eq 'uflags';
    return 2 if $word eq 'u13';
    return 3 if $word eq 'u14';
    abort("unknown special register: $word");
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
        $::image->[$::org+0] = $word >> 8;
        $::image->[$::org+1] = $word & 0xff;
    }
    $::org += 2;
}

sub emit_long {
    my $word = shift;
    if ($::pass == 2) {
        printf("%04x %08x ; %s\n", $::org, $word & 0xffff_ffff, $::line);
        $::image->[$::org+0] = ($word >> 24) & 0xff;
        $::image->[$::org+1] = ($word >> 16) & 0xff;
        $::image->[$::org+2] = ($word >> 8)  & 0xff;
        $::image->[$::org+3] = ($word >> 0)  & 0xff;
    }
    $::org += 4;
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
    $::registers->{$::scope.$name} = $reg;
}

sub scope_begin {
    $::scope = "$last_label/";
    unshift @$::scopes, $::scope;
}

sub scope_end {
    $::last_label = shift @$::scopes;
    $::last_label =~ s{/$}{};
    my $len = scalar @$::scopes;
    if ($len < 1) {
        abort("unexpected end: missing begin?");
    }
    $::scope = $::scopes->[0];
}

sub emit_op {
    my $op = shift;
    if ($::org & 1) {
        abort("instruction not on word boundary: org 0x%x", $::org);
    }
    emit_word($op);
}

sub get_list {
    my $e = shift;
    my @values = ();
    while(1) {
        my ($v, $rest) = op_value($e, 0);
        push @values, $v;
        if ($rest =~ m{^ , \s*(.*)}x) {
            $e = $1;
            next;
        }
        if ($rest eq '') {
            last;
        }
        abort("unexpected trailing '$rest'");
    }
    return @values;
}

sub get_value {
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
    elsif ($e =~ m{^ '([^']*)' \s*(.*)}xi) {
        (my $char, $rest) = ($1, $2);
        $v = ord $char;
    }
    elsif ($e =~ m{^ \.([a-z_]\w*) \s*(.*)}xi) {
        my $found = 0;
        foreach my $scope (@$::scopes) {
            if (defined $::labels->{$scope.$1}) {
                ($found, $v, $rest) = (1, $::labels->{$scope.$1}, $2);
                last
            }
        }
        if (!$found) {
            if ($::pass == 1) {
                ($v, $rest) = (0, $2);
            }
            else {
                abort("undefined symbol: %s", $1);
            }
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

sub main {
    $| = 1;
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

    foreach $::pass (1, 2) {
        $::org = 0x0000;
        foreach my $raw_line (@$lines) {
            ($::file, $::lineno, $::line) = @$raw_line;
            if ($::line =~ s{^ \.([a-z_]\w*) \s*}{}xi) {
                my $label = $1;
                $::last_label = $::scope.$label;
                if ($::pass == 1) {
                    if (exists $::labels->{$::scope.$label}) {
                        abort("symbol exists: %s", $label);
                    }
                    $::labels->{$::scope.$label} = $::org;
                }
                else {
                    print ".$label\n";
                }
            }

            next if $::line eq '';

            if ($::line =~ m{^ def \s+ (\w+) \s+ (.*)$}xi) {
                my $label = $1;
                my $expr = $2;
                if ($::pass == 1) {
                    if (exists $::labels->{$::scope.$label}) {
                        abort("symbol exists: %s", $::scope.$label);
                    }
                }
                $::labels->{$::scope.$label} = get_value($expr);
            }
            elsif ($::line =~ m{^ org \s+ (.*) $}xi) {
                $::org = get_value($1);
            }
            elsif ($::line =~ m{^ db \s+ (.*) $}xi) {
                emit_byte($_) foreach get_list($1);
            }
            elsif ($::line =~ m{^ dw \s+ (.*) $}xi) {
                foreach my $value (get_list($1)) {
                    emit_word($value);
                }
            }
            elsif ($::line =~ m{^ dl \s+ (.*) $}xi) {
                foreach my $value (get_list($1)) {
                    emit_long($value);
                }
            }
            elsif ($::line =~ m{^ ds \s+ (.*) $}xi) {
                emit_string($1);
            }
            elsif ($::line =~ m{^ align $}xi) {
                align();
            }
            elsif ($::line =~ m{^ alias \s+ r([0-9]+) \s+ ([a-z_]\w*) $}xi) {
                alias($1, $2);
            }
            elsif ($::line =~ m{^(?: begin | \{ )$}xi) {
                scope_begin();
            }
            elsif ($::line =~ m{^(?: end | \} )$}xi) {
                scope_end();
            }
            elsif ($::line =~ m{^ (\w+) \s* (.*?) $}xi) {
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
}

main();

