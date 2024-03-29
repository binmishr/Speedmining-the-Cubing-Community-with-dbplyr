
```{r,include=FALSE,echo=FALSE,message=FALSE}
##If default fig.path, then set it.
if (knitr::opts_chunk$get("fig.path") == "figure/") {
  knitr::opts_knit$set( base.dir = '/Users/hoehle/Sandbox/Blog/')
  knitr::opts_chunk$set(fig.path="figure/source/2019-05-06-wcamining/")
}
fullFigPath <- paste0(knitr::opts_knit$get("base.dir"),knitr::opts_chunk$get("fig.path"))
filePath <- file.path("","Users","hoehle","Sandbox", "Blog", "figure", "source", "2019-05-06-wcamining")

knitr::opts_chunk$set(echo = TRUE,fig.width=8,fig.height=4,fig.cap='',fig.align='center',echo=FALSE,dpi=72*2)#, global.par = TRUE)
options(width=150, scipen=1e3)

suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(magrittr))
suppressPackageStartupMessages(library(knitr))
suppressPackageStartupMessages(library(kableExtra))
suppressPackageStartupMessages(library(viridis))

##Configuration
options(knitr.table.format = "html")
theme_set(theme_minimal())
#if there are more than n rows in the tibble, print only the first m rows.
options(tibble.print_max = 10, tibble.print_min = 5)
```

## Abstract:

We use the `RMariaDB` and `dbplyr` packages to analyze the results
database of the World Cubing Association. In particular we are
interested in finding unofficial world records of fastest 3x3x3
solves, countries with large proportion of female cubers as well as
acceptable solving times before entering a WCA competition.

<center>
```{r,results='asis',echo=FALSE,fig.cap=""}
cat(paste0("<img src=\"{{ site.baseurl }}/",knitr::opts_chunk$get("fig.path"),"QUANTILEAVG-1.png\" width=\"550\">\n"))
```
</center>


{% include license.html %}



We connect to the database as follows:
```{r, echo=TRUE}
library(DBI)
library(RMariaDB)
con <- DBI::dbConnect(RMariaDB::MariaDB(), group="my-db")
```

To import the data one can either open a `mysql` shell and type SQL
commands or send the SQL query from R to the database:
```{SQL, echo=TRUE, eval=FALSE, results="hide"}
SOURCE WCA_export.sql;
```

```{r, echo=FALSE, results="hide"}
dbExecute(con, "DROP TABLE IF EXISTS Competitions2;")
```
After such an import we can view the contents of the database:
```{r, echo=TRUE}
dbListTables(con)
```

```{r}
dbListFields(con, "Results")
```
Furthermore, the table `Persons`contains additional basic information about
each player:
```{r}
dbListFields(con, "Persons")
```
Note: At WCA competitions there is no separate ranking according
to gender.


```{r, results="hide"}
##Server-side Convert year, month and day column in a proper Date
dbExecute(con, "CREATE TABLE IF NOT EXISTS Competitions2 AS SELECT *, CAST(CONCAT(year, '-', month, '-', day) AS DATE) as date FROM Competitions")

##Create index for faster joining
dbExecute(con, "CREATE INDEX IF NOT EXISTS id_hash ON Persons (id);")
dbExecute(con, "CREATE INDEX IF NOT EXISTS id_hash ON Competitions2 (id);")
dbExecute(con, "CREATE INDEX IF NOT EXISTS id_hash_p ON Results (personId);")
dbExecute(con, "CREATE INDEX IF NOT EXISTS id_hash_c ON Results (competitionId);")
```

As the next step we create tables to use with `dbplyr`. These will then
just dispatch to the database tables. For now, we work only with the
results of the 3x3x3 cubes, but will join the Results, Persons and
Competitions table in order to get relevant information about gender
of the person as well as date of the solve together with the time of
each solve.

```{r, echo=TRUE}
suppressPackageStartupMessages(library(dbplyr))
suppressPackageStartupMessages(library(dplyr))

results <- tbl(con, "Results") %>% filter(eventId == "333")
persons <- tbl(con, "Persons")
competitions <- tbl(con, "Competitions2")

##JOIN the three tables together
allResults <- results %>% inner_join(persons, by=c("personId"="id")) %>%
  inner_join(competitions, by=c("competitionId"="id"))
```

Note that `dbplyr` uses lazy evaluation, i.e. calls are not executed
before needed. However, one can with `show_query` check the SQL call,
which is used in case of evaluation. In this example the SQL query to get
the results of female cubers, i.e.:
```{r, echo=TRUE}
fwr_single <- allResults %>% filter(gender == "f", best>0)
```
in SQL looks like
```{r, echo=TRUE}
fwr_single %>% show_query()
```

## Analysing the data

We are now all ready to perform some descriptive analyses of the
data. The top-5 females according to their time for 3x3x3 single solve
is obtained by:
```{r, echo=TRUE}
fwr_single %>%
  group_by(personId) %>% top_n(-1, best) %>% ungroup %>%
  arrange(best) %>%
  select(competitionId, personName, personCountryId, best, date) %>%
  top_n(-5, best)
```
As professional data scientist one knows how important it is to
understand the data generating process and to know your data. So this
is how the 5.37s solve by Dana Yi in 2017 looks like:
<p>
<center>
<iframe width="560" height="315"
src="https://www.youtube.com/embed/WMd6JgC4DoQ" frameborder="0"
allow="accelerometer; autoplay; encrypted-media; gyroscope;
picture-in-picture" allowfullscreen></iframe>
</center>
<p>

### The evolution of the 3x3x3 single solve WR

```{r, echo=FALSE, results="hide"}
##Function to compute the indicator function, whether the sequential relative rank
##of a value is equal to one. Note: index of vectors start at 0 in Rcpp.
Rcpp::cppFunction('NumericVector sequential_is_rank1(NumericVector x) {
  int n = x.size();
  NumericVector output(n);
  double best = 1e99;

  for (int i = 0; i < n; ++i) {
     output[i] = x[i] < best;
     if (x[i] < best) { best = x[i]; }
  }
  return output;
}')
```

So at this point we force an execution of the `allResults` query and
cache the result as an object in R.  This feels slightly
disappointing, because the hope was to leave the data in the database
management system (DBMS) as long as possible, but it felt like the
most efficient way to compute sequential ranks - however, it might
have been possible to perform the sequential rank directly using SQL
statements, although I did not succeed to find the correct approach
within the available time [^1].

```{r}
allResultsTab <- allResults %>% collect()
```

Instead, the results are sorted according to their date in R and
subsequently each result is checked to see if it's sequential rank is
1, i.e. whether the time is lower than all previous results.  For this
purpose a fast Rcpp function `sequential_is_rank1` function is provided,
which computes the sequential rank of a vector of values (see [github code](`r paste0("https://raw.githubusercontent.com/hoehleatsu/hoehleatsu.github.io/master/_source/",current_input())`) for details). Note:
If we had not pulled the data into R at this point, such a computation
within R would not have been possible.

```{r, warning=FALSE}
######################################################################
## Extract all gender specific new WRs in the period
## [from_year-01-01, 2019-04-19]
##
## @param which_gender Gender to consider (either "m" or "f")
## @param from_year Start of the time period to report results for
## @return A data.frame ordered by `date` where each row corresponds
##         to a result which was a new 3x3x3 single WR among `gender`.
######################################################################
wr_evolution <- function(which_gender, from_year=2005) {
  single <- allResultsTab %>%
    filter(gender == which_gender, best>0) %>% arrange(date)

  ##Compute the sequential ranks and select only new WRs in a given time period (>= from_year)
  single_rr <- single %>%
    mutate(rank=sequential_is_rank1(best)) %>%
    filter(rank == 1,  lubridate::year(date) >= from_year)

  ##Add an extra data point at the end allowing geom_step to continue drawing the line
  df <- data.frame(personId="NA", date=as.Date("2019-04-19"), best=min(single_rr$best), rank=1, gender=which_gender)
  res <- full_join(single_rr, df, by=c("personId","date","best","rank", "gender"))
  return(res)
}

##Compute evolution for both genders and combine into one data.frame
wr <- purrr::map_df(c("f","m"), wr_evolution)
```

The evolution of the world record for males and females
over time is then easily plotted. Note: As mentioned WCA doesn't officially
distinguish between male and female results.

```{r WREVO, message=FALSE, }
suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(lubridate))
ggplot(wr, aes(x=date, y=best/100, color=gender)) + geom_step() +
  ylab("Single solve 3x3 x3 (s)") +
  xlab("Date of result") +
  scale_color_viridis(discrete=TRUE) +
  scale_x_date(breaks = seq(as.Date("2005-01-01"), as.Date("2019-04-19"), by = "2 year"), labels=year(seq(as.Date("2005-01-01"), as.Date("2019-04-19"), by = "2 year"))) +
  scale_y_continuous(limit=c(0,NA))
```
### Countries with highest proportion of female cubers

Since the overall fraction of female cubers is around 10%, we
determine the top-5 countries (with at least 50 cubers), having the
highest proportion of female cubers in the `Persons` database:

```{r, message=FALSE, warning=FALSE}
persons %>% group_by(id) %>% group_by(countryId) %>%
  summarise(n_total=n(), n_male=sum(gender=="m"), n_female=sum(gender=="f")) %>%
  mutate(`frac_female (in %)`= n_female/n_total*100)  %>% ungroup %>%
  collect() %>% ##collect nessary, otherwise it doesn't work?
  filter(n_total >= 50) %>%
  top_n(5, `frac_female (in %)`) %>%
  kable(digits=1, format = "html") %>%
  kable_styling(bootstrap_options = "striped", full_width = FALSE)
```
<p>
I find this list quite surprising and also encouraging!


### Skill level before entering a WCA competition

```{r, message=FALSE, warning=FALSE}
##Find first WCA competition of each cuber
first <- allResultsTab %>% group_by(personId) %>% select(date) %>%
  summarise(first_wca_competition = min(date))
##Form an "experience" column containing the number of years since the
##first WCA competition
allResultsTab2 <- inner_join(allResultsTab, first, by="personId") %>%
  mutate(experience=as.numeric((date - first_wca_competition)/365.25),
         resultYear=year(date))
##Look only at results with a valid average (i.e. 5 results,
##where the best and worst result are removed and the remaining 3 averaged)
allResultsTabAvg <- allResultsTab2 %>% filter(average>0)

##We will only analyse results of the last year and we will remove
#the WCA 1982 championship participants
res_lastyear <- allResultsTabAvg %>%
  filter(date >= as.Date("2018-04-19"), year(first_wca_competition)>=2003)
```
```{r}
##Quantiles to consider
q_grid <- c(0.05, 0.1, 0.5, 0.9, 0.95)
```
We then use this information to create a scatter plot with result
average (in seconds)
and corresponding experience of the cuber (in years). For better
visualization we plot the marginal
`r paste0(sprintf("%0.f%%",q_grid*100), collapse=", ")`
quantiles as smooth function of experience - this is done with
with `ggplot2`'s  `geom_quantile` function together with the argument
`method="rqss"`, which then uses the `rqss` function of the `quantreg`
package [@quantreg] to compute smooth quantile curves:

```{r QUANTILEAVG, message=FALSE, warning=FALSE}
pal <- RColorBrewer::brewer.pal(n=3, name="Set2")
##Plot quantiles
ggplot(res_lastyear, aes(x=experience, y=average/100)) + geom_point(color=pal[1], alpha=0.05) +
  geom_quantile(method = "rqss", lambda = 0.1, quantiles=q_grid, color=pal[2]) +
  coord_cartesian(ylim=c(0,60), xlim=c(0,10)) +
  xlab("Experience (years)") + ylab("Average 3x3x3 (s)")
```
We notice that the quantile curves stay more or less parallel, which
is indicative of a stable variance and skewness of the results over the range of
experiences. Focusing only on the round-1 results of those
participating for the first time in the period
from 2018-04-19 to 2019-04-19 we see that the quantiles for the average is
(in seconds) are:
```{r}
res_lastyear_newbies <- res_lastyear %>% filter(experience==0, roundTypeId==1)
```


```{r, eval=FALSE}
ggplot(res_lastyear_newbies, aes(x=average/100, y=..count../sum(..count..))) + geom_histogram(breaks=seq(0,180,by=5), fill=pal[1], alpha=0.8) + xlab("Average 3x3x3 (s)") + ylab("Proportion of results") + scale_y_continuous(labels=scales::percent) + coord_cartesian(xlim=c(0,180)) + scale_color_viridis()
```

```{r}
q <- quantile(res_lastyear_newbies$average/100, probs=c(q_grid, 0.99, 0.999))
print(q, digits=1)
```
This shows that with a 180s average one is located at
the `r sprintf("%.1f%%",100*mean(res_lastyear_newbies$average<=18000))`
quantile of all cubers entering a WCA competition. In other words: if the
comfort zone is defined as **being within the 95%
envelope**, then a ~90s average is needed before entering
a WCA competition.

To further investigate, how cubers of that skill level evolve in time, we study the
solving skills of cubers entering their first WCA competition with a
solve time between 180s and 240s. In order to reduce the
potential effect of secular trends due to, e.g., better cubes, we
consider the skill evolution of the cohort of **first time cubers** from
2015 and onwards.

```{r COHORTEVOLUTION}
##Define cohort of all cubers entering a WCA competition for the first time
cohort <- allResultsTabAvg %>% filter(year(first_wca_competition) >= 2015) %>%
  filter(experience==0,  roundTypeId==1)

##Bracket to consider (in centiseconds)
lower_bracket <- 3 * 6000
upper_bracket <- 4 * 6000

##Extract only those with an average time in my league
cohort_myleague <- cohort %>% group_by(personId) %>%
  summarise(best_average=min(average)) %>%
  filter(best_average > lower_bracket & best_average < upper_bracket)

cohort_evolution <- allResultsTabAvg %>%
  inner_join(cohort_myleague, by="personId")
```

```{r, results="hide"}
ptab <- cohort_evolution %>% group_by(personId) %>%
  distinct(competitionId) %>%
  summarise(n=n()) %$% n %>% table() %>% prop.table()
structure(sprintf("%.1f%%",ptab*100), names=names(ptab))
```

The cohort inclusion criterion provide a total of `r cohort_myleague %>% nrow()` first time
competitors in this skill bracket. Only `r sprintf("%.1f%%",100*(1- sum(ptab[1])))` of these cubers decide
to participate in further WCA competitions! The further development of
the averages of these cubers is best shown in a trajectory
plot. Note that the end of the lines does not necessarily mean that
they stopped cubing, instead it could be due to right truncation,
because only competitions until 2019-04-19 are available.

```{r TRAJPLOT, message=FALSE}
ggplot(cohort_evolution, aes(x=experience, y=average/100, color=as.factor(personId))) + geom_line() + geom_point() +
#  scale_color_viridis(discrete=TRUE, guide=FALSE) +
  scale_color_discrete(guide=FALSE) +
  scale_y_continuous(limits=c(0,NA)) +
  scale_x_sqrt() +
  ylab("Average 3x3x3 (s)") + xlab("Experience (years)") +
  geom_hline(yintercept=lower_bracket/100, lty=2, col="lightgray") +
  geom_hline(yintercept=upper_bracket/100, lty=2, col="lightgray")
```
Instead of the trajectories we can also overlay an expectation
smoother on top of the data to see how the expected average progresses
with time in the cohort. Note, that this portrays the marginal
expectation and thus is only based on cubers, who are still cubing at
that time. No adjustment for any, potentially informative, drop-out is
made.

```{r TRAJSMOOTHED, warning=FALSE, message=FALSE}
ggplot(cohort_evolution, aes(x=experience, y=average/100)) +
  geom_line(aes(color=as.factor(personId)), alpha=0.2) +
  geom_point(aes(color=as.factor(personId)),alpha=0.2) +
  scale_color_discrete(guide=FALSE) +
  geom_smooth() +
  scale_y_continuous(limits=c(0,NA)) +
  geom_hline(yintercept=lower_bracket/100, lty=2, col="lightgray") +
  geom_hline(yintercept=upper_bracket/100, lty=2, col="lightgray") +
  ylab("Average 3x3x3 (s)") + xlab("Experience (years)")
```
```{r TRAJQUANT, eval=FALSE, echo=FALSE, results="hide"}
ggplot(cohort_evolution, aes(x=experience, y=average/100)) +
  geom_line(aes(color=as.factor(personId)), alpha=0.1) +
  geom_point(aes(color=as.factor(personId)),alpha=0.1) +
  scale_color_discrete(guide=FALSE) +
  ##geom_smooth() +
  geom_quantile(method = "rqss", lambda = 1, quantiles=q_grid, color="steelblue",lwd=1.2) +
  scale_y_continuous(limits=c(0,NA), breaks=seq(5,100,by=5)) +
  geom_hline(yintercept=lower_bracket/100, lty=2, col="lightgray") +
  geom_hline(yintercept=0.5*6000/100, lty=2, col="lightgray") +
  ylab("Average 3x3x3 (s)") + xlab("Experience (years)") +
  coord_cartesian(xlim=c(0,4),ylim=c(0,30))

nrow(cohort_myleague)
ggsave(file="~/Temp/cuber-experience-smooth.png", width=8, height=4,dpi=200)
```

From the figure we notice a rapid improvement the first 6 months
after entering the first WCA competition. Hereafter results only
improve slowly.

## Discussion

Through analysis of the WCA results database it became clear that
participating in a 3x3x3 event with a 180s average ~~is uncool~~ [^2] does
not take you to winners' rostrum [^3]. The data
also show that cubers entering the world of WCA competitions with such
an average are likely to never participate in another WCA event. In
case they do, their times drop to 90-120s averages within 6 months
after which they are stuck - it is very unlikely that
they will crack the 20s barrier. To
conclude: In my situation it seems wise to practice more, before going to the first
WCA competition. `r emo::ji("smiley")`

From a data science perspective this post provided insights on using
`dbplyr` as a tidyverse frontend for SQL queries. Being an SQL novice,
I learned that generating indexes is a *must*, if you do not want to
wait forever for your *INNER JOIN*s. Furthermore, I ran into some
trouble with mutates and filters with the package, because the
produced SQL code provide empty results. It remains unclear to me if
this was due to differences in SQL DBMSs (e.g. MariaDB being
differnet from PostGres), my lack of SQL knowledge or if it's a shortcoming
of the `dbplyr` package. My conclusion is that performing the data
wrangling within the DBMS was overkill for the medium sized wca data. For larger or more structured datasets such an approach can,
however, be fruitful, because a DBMS's main purpose is to provide
efficient solutions for working with your data. Furthermore, I like
the idea of having a familiar dplyr frontend and just auto-generate an
efficient backend code (here: SQL) to do the actual wrangling. This
also provides an opportunity to get an outside-R-implementation, which
can be an important aspect

