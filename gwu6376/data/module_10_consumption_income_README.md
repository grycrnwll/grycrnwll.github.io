# Module 10 consumption and income archive

`module_10_consumption_income.csv` contains 203 complete quarterly observations from 1959Q1 through 2009Q3. Columns:

| Column | Definition |
|---|---|
| year | Calendar year |
| quarter | Quarter, 1–4 |
| realcons | Real personal consumption expenditures, billions chained 2005 US dollars, seasonally adjusted annual rate |
| realdpi | Real disposable income, billions chained 2005 US dollars, seasonally adjusted annual rate |

Source: public-domain `statsmodels.datasets.macrodata`, installed version 0.14.6. Dataset compiled by Skipper Seabold from FRED, accessed December 15, 2009. Definitions and provenance: https://www.statsmodels.org/stable/datasets/generated/macrodata.html . Exported locally November 3, 2026; that is the export date, not a new data vintage. No imputation, filtering, aggregation, or sample trimming. Year and quarter were cast to integers. The notes take natural logs of the two level series in R.

This is total aggregate consumption, not per-capita nondurable consumption. It is a new teaching illustration, not a replication of Engle–Granger (1987). The full fixed archive sample was used before examining the test result; the four-lag residual ADF baseline and 0/2/4/8 sensitivity are pedagogical specifications, not selected to obtain rejection.

To recreate the CSV with the same installed source version (instructor provenance only; student analysis is R):

```python
from statsmodels.datasets import macrodata
data = macrodata.load_pandas().data[['year', 'quarter', 'realcons', 'realdpi']].copy()
data['year'] = data['year'].astype(int)
data['quarter'] = data['quarter'].astype(int)
data.to_csv('data/module_10_consumption_income.csv', index=False)
```

The shipped CSV requires no Python, network access, FRED key, or extra R data package to use.
