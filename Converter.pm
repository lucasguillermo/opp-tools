package Converter;
use strict;
use utf8;
use Encode;
use Data::Dumper;
use File::Spec;
use FindBin qw($Bin);
use Cwd 'abs_path';
use File::Basename;
use Exporter;
use Doctidy 'doctidy';
use util::Sysexec;
use util::String;
use util::Io;
binmode STDOUT, ":utf8";
our @ISA = ('Exporter');
our @EXPORT = qw(&convert2text &convert2pdf &convert2xml &converters);

my $path = dirname(abs_path(__FILE__));
my %cfg = do "$path/config.pl";
my $RPDF = "$path/rpdf/rpdf";
my $RTF2PDF = "$path/util/rtf2pdf.sh";

my $verbosity = 0;
sub verbosity {
   $verbosity = shift if @_;
   return $verbosity;
}

my @converters_used;

sub convert2pdf {
    my $source = shift;
    my $target = shift;
    my ($basename, $filetype) = ($source =~ /^(.*?)\.?([^\.]+)$/);
    print "converting $source to pdf\n" if $verbosity;
  SWITCH: for ($filetype) {
      /html|txt/i && do {
	  push @converters_used, 'wkhtmltopdf';
          $source =~ s/([^A-Za-z0-9\/])/sprintf("%%%02X", ord($1))/seg;
          $source = File::Spec->rel2abs($source);
          # url-encode:
	  my $command = $cfg{'WKHTMLTOPDF'}
              ." --encoding utf-8"
              ." file://$source"
              ." \"$target\""
	      .' 2>&1';
	  my $out = sysexec($command, 10, $verbosity);
          print $out if $verbosity > 4;
	  die "wkhtmltopdf failed" unless -e $target;
	  return 1;
      };
      /doc/i && do {
	  push @converters_used, 'unoconv';
	  my $command = $cfg{'UNOCONV'}
	      .' -f pdf'
              .' --stdout'
	      ." \"$source\""
              .' 2>&1';
	  my $content = sysexec($command, 10, $verbosity) || '';
          unless ($content && $content =~ /%PDF/) {
              # unoconv often fails on first run, so we try again:
              $content = sysexec($command, 10, $verbosity) || '';
          }
	  die "unoconv failed"
              unless ($content && $content =~ /%PDF/);
	  return save($target, $content);
      };
      /rtf/i && do {
	  push @converters_used, 'rtf2pdf';
	  my $command = $RTF2PDF
	      ." \"$source\"" 
	      ." \"$target\""
	      .' 2>&1'; 
	  my $out = sysexec($command, 10, $verbosity);
	  print $out if $verbosity >= 4;
	  die "rtf2pdf failed" unless -e $target;
	  return 1;
      };
      /ps/i && do {
          # ps2pdf uses a made-up character map for the generated pdf,
          # so pdftohtml won't be able to extract any text info, and we
          # have to resort to OCR. Should look for a better converter.
          # (pstopdf has the same problem.)
	  push @converters_used, 'ps2pdf';
	  my $command = $cfg{'PS2PDF'}
	      ." \"$source\""
	      ." \"$target\""
	      .' 2>&1';
	  my $out = sysexec($command, 10, $verbosity) || '';
	  print $out if $verbosity >= 4;
	  die "ps2pdf failed" unless -e $target;
	  return 1;
      };
      die "$source has unsupported filetype";
  }
}

sub convert2text {
    my $filename = shift;
    my ($basename, $filetype) = ($filename =~ /^(.*?)\.?([^\.]+)$/);
    my $text;
    print "getting plain text from $filename\n" if $verbosity;
    if (!(-e "$filename")) {
	die "$filename does not exist";
    }
  SWITCH: for ($filetype) {
      /html/i && do {
	  $text = readfile($filename);
          $text = strip_tags($text);
	  last;
      };
      /pdf/i && do {
	  convert2xml($filename, "$filename.xml") or return undef;
          $text = readfile("$filename.xml");
          $text = strip_tags($text);
	  last;
      };
      /ps/i && do {
	  convert2pdf($filename, "$filename.pdf") or return undef;
	  $text = convert2text("$filename.pdf");
	  last;
      };
      /doc|rtf/i && do {
	  my $command = $cfg{'UNOCONV'}
	      .' -f html'
              .' --stdout'
	      ." \"$filename\"";
	  my $html = sysexec($command, 10, $verbosity) || '';
	  die "unoconv failed" unless $html;
          $text = strip_tags($html);
	  last;
      };
      /txt/i && do {
	  $text = readfile($filename);
	  last;
      };
      die "convert2text: unsupported filetype ($filetype): $filename";
  }
    print "$text\n" if $verbosity >= 4;
    return $text;
}

sub convert2xml {
    my $filename = shift or die "convert2xml requires filename parameter";
    my $target = shift;
    $target = "$filename.xml" unless $target;
    my ($basename, $filetype) = ($filename =~ /^(.*?)\.?([^\.]+)$/);
    print "getting XML from $filename\n" if $verbosity;
    if ($filetype =~ /pdf/i) {
        my $command = $RPDF
            ." -d$verbosity"
            ." \"$filename\""
            ." \"$target\""
            .' 2>&1';
        my $out = sysexec($command, 60, $verbosity) || '';
        print "$out\n" if $verbosity > 6;
        die "pdf conversion failed" unless -e "$target";
        add_meta($target, "converter", "rpdf");
        Doctidy::verbose(1) if $verbosity > 4;
        doctidy($target);
        return 1;
    }
    # convert other formats to PDF:
    if (convert2pdf($filename, "$filename.pdf")) {
        my $out = convert2xml("$filename.pdf", $target);
        foreach my $con (@converters_used) {
            add_meta($target, "converter", $con);
        }
        system("rm \"$filename.pdf\"");
        return $out;
    }
    die "pdf conversion failed";
}

1;

