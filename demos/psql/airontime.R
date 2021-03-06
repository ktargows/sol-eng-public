#### Package dependencies

library(dplyr)
library(ggplot2)
library(dygraphs)
library(xts)
library(DT)
library(gridExtra)

#####################################
### Database connection
#####################################

### Connect to the database

(air <- src_postgres(dbname = 'airontime', 
                     host = 'localhost', 
                     port = '5432', 
                     user = 'psql_user', 
                     password = 'ABCd4321'))


### Connect to the flights fact table

flights <- tbl(air, "flights")
dim(flights)
colnames(flights)

### Connect to the carrier lookup table
carriers <- tbl(air, "carriers")
glimpse(carriers)


#####################################
### Targeted Sample
#####################################

### Targeted Sample

query1 <- flights %>%
  select(year, month, arrdelay, depdelay, distance, uniquecarrier) %>%
  mutate(gain = depdelay - arrdelay) %>%
  filter(depdelay > 15 & depdelay < 240) %>%
  filter(dayofmonth == 1)
samp1 <- collect(query1)
show_query(query1)
dim(flights)
dim(samp1)

### 1. Filter NA's

apply(is.na(samp1), 2, sum)
samp1a <- samp1 %>%
  filter(!is.na(arrdelay) & !is.na(depdelay) & !is.na(distance))

### 2. Filter outliers

p1 <- ggplot(samp1a, aes(depdelay)) + 
  geom_density(fill = "lightblue") + 
  geom_vline(xintercept = c(15, 240), col = 'tomato') + 
  xlim(-15, 240)

p2 <- ggplot(samp1a, aes(depdelay, arrdelay)) + 
  geom_hex() +
  geom_vline(xintercept = c(15, 240), col = 'tomato') +
  geom_hline(yintercept = c(-60, 360), col = 'tomato')

grid.arrange(p1, p2, ncol=2)

samp1b <- samp1a %>%
  filter(depdelay > 15 & depdelay < 240) %>%
  filter(arrdelay > -60 & arrdelay < 360)

#### 3. Filter years

samp1b_by_year <- samp1b %>%
  group_by(year) %>%
  summarize(gain = mean(gain)) %>%
  mutate(year = as.Date(paste(year, '01-01', sep = '-')))

with(samp1b_by_year, as.xts(gain, year)) %>% 
  dygraph(main = "Gain") %>%
  dyShading("2003-01-01", "2007-01-01") %>%
  dyRangeSelector() %>%
  dyEvent(date = "2001-09-11", "9/11/2001", labelLoc = "bottom")

samp1c <- samp1b %>%
  filter(year >= 2003 & year <= 2007)

### Summary

query2 <- query1 %>%
  filter(!is.na(arrdelay) & !is.na(depdelay) & !is.na(distance)) %>%
  filter(arrdelay > -60 & arrdelay < 360) %>%
  filter(year == 2005)
samp2 <- collect(query2)
show_query(query2)


#####################################
### Joins
#####################################

### Join carrier description

query3 <- query2 %>%
  left_join(carriers, by = c('uniquecarrier' = 'code'))
samp3 <- collect(query3)
show_query(query3)

### Summarize average gain by carrier

samp3 %>%
  group_by(description) %>%
  summarize(gain = mean(gain)) %>%
  arrange(desc(gain)) %>%
  datatable


#####################################
### Random Sample
#####################################

### Random Sample

query4 <- flights %>%
  select(year, month, arrdelay, depdelay, distance, uniquecarrier) %>%
  mutate(gain = depdelay - arrdelay) %>%
  filter(depdelay > 15 & depdelay < 240) %>%
  filter(!is.na(arrdelay) & !is.na(depdelay) & !is.na(distance)) %>%
  filter(arrdelay > -60 & arrdelay < 360) %>%
  filter(dayofweek == 2) %>%
  left_join(carriers, by = c('uniquecarrier' = 'code')) %>%
  mutate(x = random()) %>%
  collapse() %>%
  filter(x < 0.05) %>%
  select(-x)
samp4 <- collect(query4)
show_query(query4)


#####################################
### Model
#####################################

### Build model

lm4 <- lm(gain ~ distance + depdelay + uniquecarrier, samp4)

### Estimates

lm4 %>%
  summary %>%
  coef %>%
  round(., 4) %>%
  data.frame %>%
  add_rownames %>%
  mutate(code = substring(rowname, 14)) %>%
  left_join(carriers, copy = TRUE) %>%
  select(rowname, description, Estimate, Std..Error, t.value, Pr...t..) %>%
  datatable()


#####################################
### Scoring
#####################################

#### Coefficient lookup table

coefs <- dummy.coef(lm4)
k <- length(coefs$uniquecarrier)
coefs_lkp <- data.frame(
  uniquecarrier = names(coefs$uniquecarrier),
  carrier_score = coefs$uniquecarrier,
  int_score = rep(coefs$`(Intercept)`, k),
  dist_score = rep(coefs$distance, k),
  delay_score = rep(coefs$depdelay, k),
  row.names = NULL, 
  stringsAsFactors = FALSE
)
head(coefs_lkp)

#### Score the database forecast performance

query5 <- flights %>%
  select(year, month, arrdelay, depdelay, distance, uniquecarrier) %>%
  mutate(gain = depdelay - arrdelay) %>%
  filter(depdelay > 15 & depdelay < 240) %>%
  filter(!is.na(arrdelay) & !is.na(depdelay) & !is.na(distance)) %>%
  filter(arrdelay > -60 & arrdelay < 360) %>%
  filter(year == 2005) %>%
  filter(dayofmonth == 2) %>%
  left_join(carriers, by = c('uniquecarrier' = 'code')) %>%
  left_join(coefs_lkp, copy = TRUE) %>%
  mutate(pred = int_score + carrier_score + dist_score * distance + delay_score * depdelay) %>%
  group_by(description) %>%
  summarize(gain = mean(1.0 * gain), pred = mean(pred))
samp5 <- collect(query5)
show_query(query5)

### Gain averages by carrier for top predicted decile

ggplot(samp5, aes(gain, pred)) + 
  geom_point(alpha = 0.75, color = 'red', shape = 3) +
  geom_abline(intercept = 0, slope = 1, alpha = 0.15, color = 'blue') +
  geom_text(aes(label = substr(description, 1, 20)), size = 4, alpha = 0.75, vjust = -1) +
  labs(title='Average Gains Forecast', x = 'Actual', y = 'Predicted')

