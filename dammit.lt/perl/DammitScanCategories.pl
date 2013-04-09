#!/usr/bin/perl

  no warnings 'uninitialized';

  use lib "/home/ezachte/lib" ;
  use EzLib ;
  ez_lib_version (8) ;
  $trace_on_exit = $true ;

  use CGI::Carp qw(fatalsToBrowser);
  use Time::Local ;
  use Net::Domain qw (hostname);

  $callsmax     = 10000 ;
  $callsmaxtest = 10000 ;
  $cmlimit      = 500 ;
  $maxlevel     = 4 ; # default

  default_argv "-j \"Nederlands_kunstschilder\"|-d 9|-c \"Nederlands_kunstschilder\"|-p nl.wikipedia.org" ;

  $timestart = time ;

  &ParseArguments ;

  &ScanCategories ;

  exit ;

# arguments checking can be improved, is not fool proof
sub ParseArguments
{
  my $options ;
  getopt ("cdow", \%options) ;

  foreach $key (keys %options)
  {
  # print "1: $key ${options {$key}}\n" ;
    $options {$key} =~ s/^\s*(.*?)\s*$/$1/ ;
    $options {$key} =~ s/^'(.*?)'$/$1/ ;
    $options {$key} =~ s/^"(.*?)"$/$1/ ;
    $options {$key} =~ s/\@/\\@/g ;
  # print "2: $key ${options {$key}}\n" ;
  }

  abort ("Specify category as: '-c \"some category\"'")    if (! defined ($options {"c"})) ;
  abort ("Invalid tree depth specified! Specify tree depth for category scan n (n between 1 and 9) as: '-d n'") if (defined ($options {"d"}) && ($options {"d"} !~ /^[1-9]$/)) ;
  abort ("Specify wiki as e.g.: '-w nl.wikipedia.org'") if (! defined ($options {"w"})) ;
  abort ("Specify output folder as : '-o [folder]'") if (! -d $options {"o"}) ;
  
  $category = $options {"c"} ;
  $depth    = $options {"d"} ;
  $path_out = $options {"o"} ;
  $wiki     = $options {"w"} ;
  $projectcode = $wiki ;

  &ValidateCategory ;

  $projectcode =~ s/wikibooks.*$/b/ ;
  $projectcode =~ s/wikinews.*$/n/ ;
  $projectcode =~ s/wikipedia.*$/z/ ;
  $projectcode =~ s/wikiquote.*$/q/ ;
  $projectcode =~ s/wikisource.*$/s/ ;
  $projectcode =~ s/wikiversity.*$/v/ ;
  $projectcode =~ s/wiktionary.*$/k/ ;
  $projectcode =~ s/wikimedia.*$/m/ ;

# if ($job eq '')
# {
#   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
#   $job = sprintf ("%04d-%02d-%02d %02d-%02d-%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec) ;
#   print "No job id (also target dir) specified: use default '$job'\n" ;
# }

  if ($depth eq '')
  { print "No depth specified for scanning category tree. Using default $maxlevel\n" ; }
  else
  { $maxlevel = $depth ; }

  $path_out = "$path_out/$category" ;

  mkdir ($path_out) ;
  if (! -d $path_out)
  { abort ("Output directory '" . $path_out . "' not found and could not be created") ; }

  $file_log        = "$path_out/scan_categories.log" ;
  $file_csv        = "$path_out/scan_categories_found_articles.csv" ;
  $file_categories = "$path_out/scan_categories_found_tree.txt" ;

  print "\n" ;
  print "Log $file_log\n" ;
  print "Csv $file_csv\n" ;
  print "Txt $file_categories\n" ;
}

#sub LogArguments
#{
#  my $arguments ;
#  foreach $arg (sort keys %options)
#  { $arguments .= " -$arg " . $options {$arg} . "\n" ; }
#  &Log ("\nArguments\n$arguments\n") ;
#}

sub ValidateCategory
{
  $url = "http://$wiki/w/api.php?action=query&format=xml&list=categorymembers&cmtitle=Category:$category&cmlimit=1" ;
  ($result, $content) = &GetPage ($category, $level, $url, $true) ;
  if ($content =~ /<categorymembers \/>/)
  {
    print "Category '$category' not found or empty on wiki '$wiki'\n" ;
    exit ;
  }
}

sub ScanCategories
{
  &OpenLog ;
  open FILE_CSV,        '>', "$file_csv" ;
  open FILE_CATEGORIES, '>', "$file_categories" ;

  &Log ("\nFetch pages from $wiki ($projectcode) for category $category, max $maxlevel levels deep.\n\n") ;
  print FILE_CATEGORIES "Fetch pages from $wiki for category $category, max $maxlevel levels deep.\n\n" ;
  print FILE_CATEGORIES "s = subcategories, a = articles\n\n" ;

  &FetchCategoryMembers ($category, 1) ;

  print FILE_CSV "# wiki:$wiki\n" ;
  print FILE_CSV "# category:$category\n" ;
  print FILE_CSV "# depth:$maxlevel\n" ;
  print FILE_CSV "# job:$job\n" ;

  foreach $article_category (sort keys %results)
  {
    $articles_found ++ ;
    print FILE_CSV "$projectcode,$article_category\n" ;
  }

  $duration = time - $timestart ;
  print FILE_CATEGORIES "\n$categories_scanned unique categories scanned, with in total $articles_found unique articles (namespace 0), in $duration seconds.\n" ;
  close FILE_CSV ;
  close FILE_CATEGORIES ;
  close FILE_LOG ;
}

sub FetchCategoryMembers
{
  my $category = shift ;
  my $level    = shift ;
  $indent  = "  " x ($level-1) ;

  if ($level > $maxlevel) { return ; }

  ($category2 = $category) =~ s/([\x80-\xFF]{2,})/&UnicodeToAscii($1)/ge ;
  return if $category2 =~ /^\s*$/ ;

  if ($queried {$category})
  {
    $indent = "  " x  ($level-1) ;
    print FILE_CATEGORIES "$indent $level '$category2' -> already queried\n" ;
    return ;
  }

  my (@categories, @articles) ;
  $categories_scanned++ ;

  $queried {$category}++ ;

  $url = "http://$wiki/w/api.php?action=query&format=xml&list=categorymembers&cmtitle=Category:$category&cmlimit=$cmlimit" ;
  $continueprev = "" ;
  while ($url ne "")
  {
    $calls ++ ;
    if ($calls > $callsmaxtest) { print FILE_CATEGORIES "Number of api calls exceeds test limit $calls\n" ; last ; }
    if ($calls > $callsmax) { &Abort ("Number of api calls exceeds safety limit $calls") ; }
    $content = "" ;
    ($result, $content) = &GetPage ($category, $level, $url, $true) ;

    &Log2 ("\n\n$url\n$result $content\n\n") ;

  # $content =~ s/([\x80-\xFF]{2,})/&UnicodeToAscii($1)/ge ;

    $continue = "" ;
    if ($content =~ /cmcontinue/)
    {
      $continue = $content ;
      $continue =~ s/^.*?query-continue>(.*?)<\/query-continue>.*$/$1/ ;
      $continue =~ s/^.*?cmcontinue="([^\"]*)".*$/$1/ ;
      &Log ("+++ $indent $level continue with '$continue'\n") ;
      $url = "http://$wiki/w/api.php?action=query&format=xml&list=categorymembers&cmtitle=Category:$category&cmlimit=$cmlimit&cmcontinue=$continue" ;
    }

    else
    { $url = "" ; }

    if (($continue eq $continueprev) && ($continue ne ""))
    {
      &Log ("$indent $level Loop encountered\n\ncontinue: $continue\n\nprevious string'$continueprev'\n\ncontent: '$content'") ;
      $content = "" ;
      $url = "" ;
    }

    $members = "" ;
    if ($content =~ /categorymembers/)
    {
      $members = $content ;
      $members =~ s/^.*?categorymembers>(.*?)<\/categorymembers>.*$/$1/ ;
      @categories = &GetCategories ($category, $level, $members) ;
      @articles   = &GetArticles   ($members) ;
      foreach $article (@articles)
      {
        $article  =~ s/,/\%2C/g ;
        $article  =~ s/ /_/g ;
        $category =~ s/,/\%2C/g ;
        $category =~ s/ /_/g ;
        $results {"$article,$category"}++ ;
      }
    }
    else
    { $url = "" ; }

    $continueprev = $continue ;
  }

  print FILE_CATEGORIES "$indent $level '$category2' -> subcats:" . ($#categories+1) . " articles:" . ($#articles+1) . "\n" ;
  foreach $subcategory (sort @categories)
  {
    if (($level < $maxlevel) && ($subcategory !~ /(?:National_Inventors_Hall_of_Fame_inductees|Inventors|Directors)/))
    { &FetchCategoryMembers ($subcategory, $level+1) ; }
  }
}

sub GetPage
{
  my $category = shift ;
  my $level    = shift ;

  $indent  = "  " x ($level-1) ;

  use LWP::UserAgent;
  use HTTP::Request;
  use HTTP::Response;
  use URI::Heuristic;

  my $raw_url = shift ;
  my $is_html = shift ;
  my ($success, $content, $attempts) ;
  my $file = $raw_url ;

  my $url = URI::Heuristic::uf_urlstr($raw_url);

  my $ua = LWP::UserAgent->new();
  $ua->agent("Wikimedia Perl job / EZ");
  $ua->timeout(60);

  my $req = HTTP::Request->new(GET => $url);
  $req->referer ("http://infodisiac.com");

  my $succes = $false ;

  my $file2 = $file ;
  $file2 =~ s/^.*?api/api/ ;
  $file2 =~ s/([\x80-\xFF]{2,})/&UnicodeToAscii($1)/ge ;
  (my $category2 = $category) =~ s/([\x80-\xFF]{2,})/\?/g ;
  print "GET $indent $level $category2" ;
  &Log2 ("\n$indent $level $category -> '$file2'") ;

  for ($attempts = 1 ; ($attempts <= 2) && (! $succes) ; $attempts++)
  {
    if ($requests++ % 2 == 2)
    { sleep (1) ; }

    my $response = $ua->request($req);
    if ($response->is_error())
    {
      if (index ($response->status_line, "404") != -1)
      { &Log (" -> 404\n") ; }
      else
      { &Log (" -> error: \nPage could not be fetched:\n  '$raw_url'\nReason: "  . $response->status_line . "\n") ; }
      return ($false) ;
    }
    # else
    # { &Log ("\n") ; }

    $content = $response->content();

    # if ($is_html && ($content !~ m/<\/html>/i))
    # {
    #   &Log ("Page is incomplete:\n  '$raw_url'\n") ;
    #   next ;
    # }

    $succes = $true ;
  }

  if (! $succes)
  { &Log (" -> error: \nPage not retrieved after " . (--$attempts) . " attempts !!\n\n") ; }
  else
  { &Log (" -> OK\n") ; }

  return ($succes,$content) ;
}

# make more flexible some day, now assumes current xml format
sub GetCategories
{
  my $category = shift ;
  my $level    = shift ;
  my $members  = shift ;
  my @categories ;
  my $subcategories ;
  $members =~ s/<cm[^>]*? ns="14" title="([^>"]+)".*?>/($a=$1, $a=~ s#^[^:]+:##, push @categories, $a)/ge ;
#  if ($#categories > -1)
#  {
#    foreach $category (@categories)
#    {
#      $category2 = $category ;
#      $category2 =~ s/,/%2C/g ;
#      $subcategories .= "$category2, " ;
#    }
#    $subcategories =~ s/,$// ;
#    print FILE_CATEGORIES "$level: Category '$category': subcategories\n'$subcategories'\n" ;
#  }
#  else
#  {  print FILE_CATEGORIES "$level: Category '$category': no subcategories\n" ; }
  foreach $category (@categories)
  { $category =~ s/\&\#039;/'/g ; }
  return (@categories) ;
}

# make more flexible some day, now assumes current xml format
sub GetArticles
{
  my $members = shift ;
  my @articles ;
  $members =~ s/<cm[^>]*? ns="\d+" title="([^"]+)".*?>/(push @articles, $1)/ge ;
  foreach $article (@articles)
  { $article =~ s/\&\#039;/'/g ; }
  return (@articles) ;
}

sub ConvertDate
{
  my $date = shift ;
  my $time = substr ($date,0,5) ;
  my $hour = substr ($time,0,2) ;
  $date =~ s/^[^\s]* // ;
  ($day,$month,$year) = split (' ',$date) ;

     if ($month =~ /^january$/i)    { $month = 1 ; }
  elsif ($month =~ /^february$/i)   { $month = 2 ; }
  elsif ($month =~ /^march$/i)      { $month = 3 ; }
  elsif ($month =~ /^april$/i)      { $month = 4 ; }
  elsif ($month =~ /^may$/i)        { $month = 5 ; }
  elsif ($month =~ /^june$/i)       { $month = 6 ; }
  elsif ($month =~ /^july$/i)       { $month = 7 ; }
  elsif ($month =~ /^august$/i)     { $month = 8 ; }
  elsif ($month =~ /^september$/i)  { $month = 9 ; }
  elsif ($month =~ /^october$/i)    { $month = 10 ; }
  elsif ($month =~ /^november$/i)   { $month = 11 ; }
  elsif ($month =~ /^december$/i)   { $month = 12 ; }
  else { &Log ("Invalid month '$month' encountered\n") ; exit ; }

  $date = sprintf ("%04d/%02d/%02d",$year,$month,$day) ;
  $date2 = sprintf ("=date(%04d,%02d,%02d)",$year,$month,$day) ; # excel

  if ("$date $time" gt $date_time_max)
  { $date_time_max = "$date $time" ; }
  return ($date,$date2,$time,$hour) ;
}

sub OpenLog
{
  $fileage  = -M $file_log ;
  if ($fileage > 5)
  {
    open "FILE_LOG", "<", $file_log || abort ("Log file '$file_log' could not be opened.") ;
    @log = <FILE_LOG> ;
    close "FILE_LOG" ;
    $lines = 0 ;
    open "FILE_LOG", ">", $file_log || abort ("Log file '$file_log' could not be opened.") ;
    foreach $line (@log)
    {
      if (++$lines >= $#log - 5000)
      { print FILE_LOG $line ; }
    }
    close "FILE_LOG" ;
  }
  open "FILE_LOG", ">>", $file_log || abort ("Log file '$file_log' could not be opened.") ;
  &Log ("\n\n===== Scan Wikipedia Categories / " . date_time_english (time) . " =====\n\n") ;
}

# translates one unicode character into plain ascii
sub UnicodeToAscii {
  my $unicode = shift ;

  my $char = substr ($unicode,0,1) ;
  my $ord = ord ($char) ;
  my ($c, $value, $html) ;

  if ($ord < 128)         # plain ascii character
  { return ($unicode) ; } # (will not occur in this script)
  else
  {
    if    ($ord >= 252) { $value = $ord - 252 ; }
    elsif ($ord >= 248) { $value = $ord - 248 ; }
    elsif ($ord >= 240) { $value = $ord - 240 ; }
    elsif ($ord >= 224) { $value = $ord - 224 ; }
    else                { $value = $ord - 192 ; }

    for ($c = 1 ; $c < length ($unicode) ; $c++)
    { $value = $value * 64 + ord (substr ($unicode, $c,1)) - 128 ; }

    if ($value < 256)
    { return (chr ($value)) ; }

    # $unicode =~ s/([\x80-\xFF])/("%".sprintf("%02X",$1))/gie ;
    return ($unicode) ;
  }
}

sub Log
{
  $msg = shift ;
  print FILE_LOG $msg ;
  $msg =~ s/([\x80-\xFF])/("%".sprintf("%02X",$1))/gie ;
  print $msg ;
}

sub Log2
{
  $msg = shift ;
  print FILE_LOG $msg ;
}

sub Abort
{
  $msg = shift ;
  print "Abort script\nError: $msg\n" ;
  print LOG "Abort script\nError: $msg\n" ;
  exit ;
}

