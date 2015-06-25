wikistats=/a/wikistats_git
squids=$wikistats/squids
csv=$squids/csv
htdocs=stat1001.eqiad.wmnet::srv/stats.wikimedia.org/htdocs/
archive=dataset1001::pagecounts-ez

cd $csv
zip csv_squids_daily_visits_per_country.zip  SquidDataVisitsPerCountryDaily.csv
rsync csv_squids_daily_visits_per_country.zip $archive/wikistats

