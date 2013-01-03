package PageViews::Model;
use strict;
use warnings;
use Time::Piece;
use Data::Dumper;

sub new {
  my ($class) = @_;
  my $raw_obj = {
    counts => {},
  };
  my $obj     = bless $raw_obj,$class;
  return $obj;
};

sub process_line {
  my ($self,$line) = @_;
  my @fields = split(/\s/,$line);
  #use Data::Dumper;
  #warn Dumper \@fields;
  my $time    = $fields[2];
  my $url     = $fields[8];
  my $country = $fields[14];
  return if $country eq "--";

  #warn "[DBG] line = $line";
  #warn "[DBG] country = $country";
  #warn "[DBG] url     = $url    ";
  #warn "[DBG] time    = $time   ";

  my $tp    = Time::Piece->strptime($time,"%Y-%m-%dT%H:%M:%S.000");
  my $ymd = $tp->year."-".$tp->mon; # = ..

  $self->{counts}->{$ymd}->{$country}++;
};

sub process_file {
  my ($self,$filename) = @_;
  open IN, "-|", "gzip -dc $filename";
  while( my $line = <IN>) {
    $self->process_line($line);
  };
};

sub process_files  {
  my ($self, $params) = @_;
  for my $gz_logfile (split(/\n/,`ls $params->{logs_path}/*.gz`) ) {
    $self->process_file($gz_logfile);
  };
};


sub get_data {
  my ($self) = @_;

  # origins are wikipedia languages present

  my $data = [];

  my $languages_present_uniq = {};
  my @months_present = sort { $a cmp $b }  keys %{ $self->{counts} };

  my $month_totals = {};

  # mark all languages present in a hash
  # calculate month totals
  for my $month ( @months_present ) {
    for my $language ( keys %{ $self->{counts}->{$month} } ) {
      $languages_present_uniq->{$language} = 1;
      $month_totals->{$month} += 
        $self->{counts}->{$month}->{$language};
    };
  };

  my @unsorted_languages_present = keys %$languages_present_uniq;


  for my $month ( @months_present ) {
    my   $new_row = [];
    push @$new_row, $month;
    for my $idx_language ( 0..$#unsorted_languages_present ) {
      my $language = $unsorted_languages_present[$idx_language];
      # hash containing actual count, percentage of monthly total, increase over past month
      my $percentage_of_monthly_total ;
      my $monthly_delta               ;
      my $monthly_count               ;
      my $monthly_count_previous      ;

      if(@$data > 0) {
        warn "[DBG] idx_language = $idx_language";
        #warn Dumper($data->[-1]->[$idx_language]);
        warn Dumper $data->[-1];
        $monthly_count_previous = $data->[-1]->[$idx_language + 1]->{monthly_count} // 0;
      } else {
        $monthly_count_previous = 0;
      };
      $monthly_count               = $self->{counts}->{$month}->{$language}          // 0;
      $percentage_of_monthly_total = $month_totals->{$month}
                                     ? sprintf("%.2f",$monthly_count / $month_totals->{$month} // 0)
                                     : "--";

      # safety check
      # if we have at least one month to compare to
      # and the previous month has a non-zero count

      warn "[DBG] monthly_count_previous = $monthly_count_previous";
      $monthly_delta               = ( $monthly_count_previous > 0 && @$data > 0 )
                                     ? sprintf("%.2f",
                                         ($monthly_count - $monthly_count_previous )/
                                         $monthly_count_previous 
                                       )
                                     : "--";

      push @$new_row, {
        monthly_count               => $monthly_count,
        monthly_delta               => $monthly_delta,
        percentage_of_monthly_total => $percentage_of_monthly_total,
      };
    };
    push @$data , $new_row;
  };

  # pre-pend headers
  unshift @$data, ['month' , @unsorted_languages_present ];

  return {
    data => $data,
  };
};

1;
