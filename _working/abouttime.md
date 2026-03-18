---
title: "It's About Time (Series): A Simple Correction for Difference-in-Difference Estimators"
collection: working
category: manuscripts
permalink: /working/abouttime
paperurl: 'http://grycrnwll.github.io/files/abouttime.pdf'
date: 2025-12-31
status: 'Editing'
abstract: This paper reconsiders the difference-in-differences (DiD) research design for panel data, particularly when serial correlation stems from first-order model misspecification (i.e., dependence in $y_t$ rather than exclusively in $\epsilon_t$). When time-series issues like this are overlooked, the traditional parallel trends assumption is insufficient. In fact, for most panel applications ($T>2$ periods), DiD designs will misidentify and inflate a time-invariant treatment effect. To correct this, we show that DiD assumptions should be modified for dynamic panels and how explicitly accounting for temporal dependence in the design can recover the true, dynamically-robust effect. We evaluate a simple modification to DiD designs through Monte Carlo simulations and then explore its implications with empirical examples. Two examples leverage a policy shock used in recent literature to reevaluate the impact of household credit constraints on outcomes like state-level GDP growth and labor market participation. When we implement the proposed modification, which can be as simple as incorporating a lagged outcome and group interaction into a DiD model, the results illustrate a reduction in bias predicted by theory, yielding a more generalizable estimator for most applications. Finally, we find synthetic DiD and synthetic control methods do not remedy this particular issue, as similar modifications (e.g., pre-whitening) are needed to address temporal dependence in the outcome. 
---