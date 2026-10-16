#!/usr/bin/env bash
# Required Notice: Copyright 2026 stop-loss-enjoyer
# Plainlines is source-available under the PolyForm Shield License 1.0.0.
#
# audit.sh: source audit for Plainlines (rules of the project).
# Usage: ./audit.sh [file-or-dir ...]   (default: src/)   Exit 0 clean, 1 on violations.
# One line per violation: file:line: reason.
#
# Rules: no #import; no WebRequest, Socket*, SendMail, SendNotification, SendFTP;
# no FILE_COMMON, FileCopy, FileMove; no __DATE__, __DATETIME__, __MQLBUILD__;
# OrderSend, OrderSendAsync, CTrade only in the single file below.
# A #define PL_DEV_LOG, PL_RELEASE or PL_ALLOW_REAL in any scanned file is refused (build.sh sets the build mode in its temporary copy).
# ACCOUNT_LOGIN only in src/Terminal/Account.mqh (it holds the number in memory only);
# ACCOUNT_NAME (the owner's real name) nowhere.
#
# What is handled: // and /* */ comments are stripped, and the contents of string and
# character literals are blanked (so "WebRequest" in a message or a comment does not
# fail), line numbers are preserved. Matching is by whole identifier, so a variable
# named mySendMailFlag does not match, but a variable named exactly SendMail does.
# Backslash-newline line continuations are joined before scanning (line numbers kept),
# so a directive split with a trailing backslash is still seen. Local #include "x" files
# are scanned too, even when they live outside the scanned tree.
# Not handled: macro tricks (#define W WebRequest then W(...)), identifiers built by
# token pasting, literal flag values (FileOpen(n, FILE_WRITE|4096) equals FILE_COMMON;
# any integer literal inside a one-line FileOpen call is flagged (including +N and shifts), but multi-line calls and
# constants hidden behind a variable are not).
#
# Standard includes: any path with a ".." segment, a leading "/" or a drive letter is
# rejected. #include <X> must start with an allowlisted prefix (below).
# Choice: allowlist, not denylist. WinAPI/ is explicitly forbidden. Files/ is not
# allowed (it wraps file I/O where FILE_COMMON could be passed from a variable).
# If the MetaEditor Include copy exists, every allowed standard include is resolved
# transitively and the audit fails if any file in the chain contains #import or
# includes WinAPI/ (rule 1: "including via foreign #include"); both <...> and "..."
# includes inside the standard headers are followed. If the copy is missing,
# this check is skipped with a notice on stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The only file allowed to use OrderSend, OrderSendAsync, CTrade (relative to repo root).
export AUDIT_SEND_ORDER_FILE="${AUDIT_SEND_ORDER_FILE:-src/Trade/SendOrderSafe.mqh}"
export AUDIT_ACCOUNT_FILE="${AUDIT_ACCOUNT_FILE:-src/Terminal/Account.mqh}"
export AUDIT_ROOT="${AUDIT_ROOT:-$ROOT}"
export AUDIT_INCLUDE_DIR="${AUDIT_INCLUDE_DIR:-$HOME/.local/share/plainlines-build/MQL5/Include}"
# Allowed standard include prefixes (case-insensitive, relative to MQL5/Include).
# Trade/ Controls/ Canvas/ Arrays/ ChartObjects/ Object.mqh as agreed; plus
# StdLibErr.mqh (pulled in by Object.mqh), Strings/, Generic/, Math/ (pure computation).
export AUDIT_ALLOW='Trade/ Controls/ Canvas/ Arrays/ ChartObjects/ Object.mqh StdLibErr.mqh Strings/ Generic/ Math/'

[[ $# -gt 0 ]] || set -- "$ROOT/src"
exec perl -e '
use strict; use warnings;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
my $root = $ENV{AUDIT_ROOT};
my $sendfile = abs_path("$root/$ENV{AUDIT_SEND_ORDER_FILE}") // "$root/$ENV{AUDIT_SEND_ORDER_FILE}";
my $acctfile = abs_path("$root/$ENV{AUDIT_ACCOUNT_FILE}") // "$root/$ENV{AUDIT_ACCOUNT_FILE}";
my $incdir = $ENV{AUDIT_INCLUDE_DIR};
my @allow = map { lc } split / /, $ENV{AUDIT_ALLOW};
my @viol; my $nfiles = 0;

sub slurp { open(my $f, "<:raw", $_[0]) or die "cannot read $_[0]: $!\n"; local $/; my $t = <$f>; close $f;
  # MQL files may be UTF-16 with BOM or UTF-8 with BOM
  if ($t =~ s/^\xFF\xFE//) { require Encode; $t = Encode::encode("UTF-8", Encode::decode("UTF-16LE", $t)); }
  elsif ($t =~ s/^\xFE\xFF//) { require Encode; $t = Encode::encode("UTF-8", Encode::decode("UTF-16BE", $t)); }
  $t =~ s/^\xEF\xBB\xBF//; return $t; }

# Joins backslash-newline continuations; the removed newlines are appended after the
# joined line so line numbers of later lines stay the same.
sub joinlines {
  my ($t) = @_; my @l = split /\n/, $t, -1; my $o = ""; my ($acc, $k) = ("", 0);
  for my $i (0 .. $#l) { my $line = $l[$i]; my $cr = ($line =~ s/\r$//) ? "\r" : "";
    if ($i < $#l && $line =~ /(?<!\\)(?:\\\\)*\\$/) { $line =~ s/\\$//; $acc .= $line; $k++; next; }
    $o .= $acc . $line . $cr . ("\n" x $k) . ($i < $#l ? "\n" : ""); ($acc, $k) = ("", 0); }
  return $o; }

# Returns text with comments removed and literal contents blanked; newlines kept.
sub strip {
  my ($t) = @_; my $o = ""; my $n = length $t; my $i = 0; my $bol = 1; my $dir = 0;
  while ($i < $n) {
    my $c = substr($t, $i, 1); my $d = $i + 1 < $n ? substr($t, $i + 1, 1) : "";
    if ($bol) { $bol = 0; my $rest = substr($t, $i, 40); $dir = ($rest =~ /^[ \t]*#[ \t]*(include|import)\b/) ? 1 : 0; }
    if ($c eq "/" && $d eq "/") { $i++ while $i < $n && substr($t, $i, 1) ne "\n"; next; }
    if ($c eq "/" && $d eq "*") { $i += 2; while ($i < $n && substr($t, $i, 2) ne "*/") { $o .= "\n" if substr($t, $i, 1) eq "\n"; $i++; } $i += 2; $o .= " "; next; }
    if ($c eq "\"" && $dir) {   # include/import literal: copied verbatim, no comment detection inside
      $o .= $c; $i++;
      while ($i < $n) { my $x = substr($t, $i, 1); last if $x eq "\n"; $o .= $x; $i++; if ($x eq "\"") { last; } }
      next; }
    if (($c eq "\"" || $c eq "\x27") && !$dir) {
      $o .= $c; $i++;
      while ($i < $n) { my $x = substr($t, $i, 1);
        if ($x eq "\\") { $o .= " "; $i++; if ($i < $n) { my $y = substr($t, $i, 1); $o .= ($y eq "\n" ? "\n" : " "); $i++; } next; }
        if ($x eq $c) { $o .= $c; $i++; last; }
        if ($x eq "\n") { last; }
        $o .= " "; $i++; }
      next; }
    if ($c eq "\n") { $bol = 1; }
    $o .= $c; $i++;
  }
  return $o;
}

# Case-insensitive path resolution under a base dir (MQL include names are Windows style).
sub resolve_ci { my ($base, $rel) = @_; my $cur = $base;
  for my $part (grep { length } split m{/}, $rel) {
    return undef unless -d $cur; opendir(my $d, $cur) or return undef; my ($hit) = grep { lc($_) eq lc($part) } readdir $d; closedir $d;
    return undef unless defined $hit; $cur = "$cur/$hit"; }
  return -e $cur ? $cur : undef; }

sub allowed_std { my ($p) = @_; my $l = lc $p; for my $a (@allow) { return 1 if ($a =~ m{/$} ? index($l, $a) == 0 : $l eq $a); } return 0; }

sub bad_path { my ($r) = @_; return 1 if $r =~ m{^/} || $r =~ m{^[A-Za-z]:}; return (grep { $_ eq ".." } split m{/}, $r) ? 1 : 0; }
sub relinc { my ($abs) = @_; my $b = abs_path($incdir) // $incdir; return index($abs, "$b/") == 0 ? substr($abs, length($b) + 1) : undef; }

my %seen;
# $path: resolved absolute header path; $rel: its name relative to the include dir.
sub walk_std { my ($path, $rel, $chain, $origin) = @_;
  my $abs = abs_path($path) // $path;
  return if $seen{$abs}++;
  my $s = strip(joinlines(slurp($path))); my $ln = 0;
  for my $line (split /\n/, $s, -1) { $ln++;
    if ($line =~ /^\s*#\s*import\b/) { push @viol, "$origin: #import in standard include $rel (via $chain), $path:$ln"; }
    my ($r, $quoted);
    if ($line =~ /^\s*#\s*include\s*<([^>]+)>/) { $r = $1; }
    elsif ($line =~ /^\s*#\s*include\s*"([^"]+)"/) { $r = $1; $quoted = 1; }
    else { next; }
    $r =~ s{\\}{/}g;
    if ($r =~ m{^/} || $r =~ m{^[A-Za-z]:}) { push @viol, "$origin: standard include $rel has absolute include path $r"; next; }
    my $t;
    if ($quoted) { $t = resolve_ci(dirname($path), $r) // resolve_ci($incdir, $r); }
    else { (my $x = $r) =~ s{^\./}{}; $t = bad_path($x) ? undef : resolve_ci($incdir, $x); if (bad_path($x)) { push @viol, "$origin: standard include $rel has include path traversal <$r>"; next; } }
    next unless defined $t;
    my $ta = abs_path($t) // $t; my $tr = relinc($ta);
    if (!defined $tr) { push @viol, "$origin: standard include $rel includes $r outside the Include folder"; next; }
    if ($tr =~ m{^winapi/}i) { push @viol, "$origin: standard include $rel pulls in forbidden $tr"; next; }
    walk_std($t, $tr, "$chain > $tr", $origin); } }

my @rules = (
  [qr/^\s*#\s*import\b/, "#import is forbidden"],
  [qr/\bWebRequest\b/, "WebRequest is forbidden"],
  [qr/\bSocket\w*\b/, "Socket functions are forbidden"],
  [qr/\bSendMail\b/, "SendMail is forbidden"],
  [qr/\bSendNotification\b/, "SendNotification is forbidden"],
  [qr/\bSendFTP\b/, "SendFTP is forbidden"],
  [qr/\bFILE_COMMON\b/, "FILE_COMMON is forbidden (writes outside MQL5/Files)"],
  [qr/\bFileCopy\b/, "FileCopy is forbidden"],
  [qr/\bFileMove\b/, "FileMove is forbidden"],
  [qr/\b__DATE__\b/, "__DATE__ breaks reproducible builds"],
  [qr/\b__DATETIME__\b/, "__DATETIME__ breaks reproducible builds"],
  [qr/\b__MQLBUILD__\b/, "__MQLBUILD__ breaks reproducible builds"],
  [qr/\bFileOpen\s*\(.*(?<![\w.])(?:0[xX][0-9a-fA-F]+|\d+)(?![\w.])/, "FileOpen with a numeric literal (use named FILE_* and CP_* constants)"],
  [qr/^\s*#\s*define\s+PL_DEV_LOG\b/, "PL_DEV_LOG is defined: the development channel must be off in a release"],
  [qr/^\s*#\s*define\s+PL_RELEASE\b/, "PL_RELEASE is defined in source: only ./build.sh --release may set it"],
  [qr/^\s*#\s*define\s+PL_ALLOW_REAL\b/, "PL_ALLOW_REAL is defined: the switch is gone, real accounts need ./build.sh --release"],
  [qr/\bACCOUNT_NAME\b/, "ACCOUNT_NAME (the real name of the owner) is forbidden"],
);
my @acct = ([qr/\bACCOUNT_LOGIN\b/, "ACCOUNT_LOGIN outside Terminal/Account.mqh"]);
my @trade = ([qr/\bOrderSendAsync\b/, "OrderSendAsync outside SendOrderSafe"], [qr/\bOrderSend\b/, "OrderSend outside SendOrderSafe"], [qr/\bCTrade\b/, "CTrade outside SendOrderSafe"]);

my @files; my %queued;
sub enqueue { my ($p) = @_; my $a = abs_path($p) // $p; return if $queued{$a}++; push @files, $p; }
sub collect { my ($p) = @_;
  if (-d $p) { opendir(my $d, $p) or die "cannot open $p\n"; for my $e (sort grep { !/^\./ } readdir $d) { collect("$p/$e"); } closedir $d; }
  elsif (-f $p && $p =~ /\.mq[h5]$/i) { enqueue($p); }
  elsif (!-e $p) { die "audit: no such path: $p\n"; } }
collect($_) for @ARGV;

my $std_skipped = 0;
for (my $fi = 0; $fi < @files; $fi++) { my $file = $files[$fi];
  $nfiles++;
  my $abs = abs_path($file) // $file; my $is_send = ($abs eq $sendfile); my $is_acct = ($abs eq $acctfile);
  my $s = strip(joinlines(slurp($file))); my $ln = 0;
  for my $line (split /\n/, $s, -1) { $ln++;
    for my $r (@rules) { push @viol, "$file:$ln: $r->[1]" if $line =~ $r->[0]; }
    unless ($is_acct) { for my $r (@acct) { push @viol, "$file:$ln: $r->[1]" if $line =~ $r->[0]; } }
    unless ($is_send) { for my $r (@trade) { push @viol, "$file:$ln: $r->[1]" if $line =~ $r->[0]; } }
    if ($line =~ /^\s*#\s*include\s*<([^>]+)>/) { (my $r = $1) =~ s{\\}{/}g; $r =~ s{^\./}{};
      if (bad_path($r)) { push @viol, "$file:$ln: include <$r> uses path traversal or an absolute path, which is forbidden"; }
      elsif ($r =~ m{^winapi/}i) { push @viol, "$file:$ln: include <$r> is forbidden (WinAPI)"; }
      elsif (!allowed_std($r)) { push @viol, "$file:$ln: include <$r> is outside the allowlist"; }
      elsif (-d $incdir) { my $t = resolve_ci($incdir, $r); if (defined $t) { my $tr = relinc(abs_path($t) // $t) // $r; walk_std($t, $tr, $tr, "$file:$ln"); } }
      else { $std_skipped = 1; } }
    elsif ($line =~ /^\s*#\s*include\s*"([^"]+)"/) { (my $r = $1) =~ s{\\}{/}g;
      my $t = dirname($file) . "/$r";
      if (-f $t) { enqueue($t); }
      else { push @viol, "$file:$ln: unresolved local include \"$r\""; } }
  }
}
print STDERR "audit: notice: $incdir missing, transitive include check skipped\n" if $std_skipped;
if (@viol) { print "$_\n" for @viol; print STDERR "audit: FAIL (" . scalar(@viol) . " violation(s) in $nfiles file(s))\n"; exit 1; }
print "audit: OK ($nfiles file(s))\n"; exit 0;
' -- "$@"
