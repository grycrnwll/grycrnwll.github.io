# Markdown Formatting Instructions for Collapsible Abstracts

This document provides instructions for implementing collapsible abstracts for publications and projects on the website.

## HTML Details/Summary Approach

The most widely supported method for creating collapsible content in Markdown/HTML is using the HTML5 `<details>` and `<summary>` elements:

```html
<details>
<summary>Click to expand abstract</summary>

Your abstract content goes here. This can include:
- Multiple paragraphs
- **Bold text** and *italic text*
- [Links](https://example.com)
- Lists and other Markdown formatting

This content will be hidden by default and can be toggled by clicking the summary.
</details>
```

## For Publications (_publications/*.md)

Add collapsible abstracts to publication entries by modifying the front matter and content:

```markdown
---
title: "Your Publication Title"
collection: publications
permalink: /publication/2024-paper-title
excerpt: 'Brief description for listings'
date: 2024-01-15
venue: 'Journal Name'
paperurl: 'http://link-to-paper.com'
citation: 'Your Name. (2024). "Paper Title." <i>Journal Name</i>. 1(1).'
---

Brief description of the paper for the main listing.

<details>
<summary><strong>Abstract</strong></summary>

This is the full abstract of your paper. It can be quite long and detailed, 
describing the methodology, findings, and implications of your research. 

The abstract will be hidden by default and users can click to expand it 
if they want to read more details about the paper.
</details>

[Download paper here](http://link-to-paper.com)
```

## For Projects (_working/*.md)

Similar approach for working papers and projects:

```markdown
---
title: "Project Title"
collection: working
permalink: /working/project-name
excerpt: 'Brief project description'
---

Brief project overview for the listing page.

<details>
<summary><strong>Project Abstract</strong></summary>

Detailed description of the project, including:
- Research questions
- Methodology 
- Current status
- Expected outcomes
- Timeline

This provides more context while keeping the main page clean.
</details>

<details>
<summary><strong>Technical Details</strong></summary>

Additional technical information such as:
- Data sources
- Software/tools used
- Statistical methods
- Computational requirements

</details>
```

## Styling Options

### Custom CSS (Optional)

If you want to customize the appearance, you can add CSS to your `_sass/` files:

```css
details {
    margin: 1em 0;
    padding: 1em;
    border: 1px solid #ddd;
    border-radius: 4px;
    background-color: #f9f9f9;
}

details summary {
    font-weight: bold;
    cursor: pointer;
    padding: 0.5em;
    background-color: #e9ecef;
    border-radius: 4px;
    margin: -1em -1em 1em -1em;
}

details summary:hover {
    background-color: #dee2e6;
}

details[open] summary {
    border-bottom: 1px solid #ddd;
}
```

### Icon Indicators

Add icons to make the collapsible nature more obvious:

```html
<details>
<summary>📄 <strong>Abstract</strong></summary>
Content here...
</details>

<details>
<summary>🔧 <strong>Technical Details</strong></summary>
Technical content here...
</details>
```

## Implementation Notes

1. **Browser Support**: The `<details>`/`<summary>` elements are supported in all modern browsers
2. **Accessibility**: These elements are accessible by default and work with screen readers
3. **Jekyll Compatibility**: This HTML works seamlessly within Jekyll Markdown files
4. **GitHub Pages**: No additional plugins required - works out of the box

## Example Implementation

Here's a complete example of how a publication file might look:

```markdown
---
title: "Machine Learning Approaches to Economic Forecasting"
collection: publications
permalink: /publication/2024-ml-forecasting
excerpt: 'Application of modern ML techniques to macroeconomic forecasting.'
date: 2024-03-15
venue: 'Journal of Applied Econometrics'
paperurl: 'https://doi.org/10.1002/jae.example'
citation: 'Cornwall, G. (2024). "Machine Learning Approaches to Economic Forecasting." <i>Journal of Applied Econometrics</i>. 45(2), 123-145.'
---

This paper explores the application of machine learning techniques to improve macroeconomic forecasting accuracy.

<details>
<summary>📄 <strong>Abstract</strong></summary>

We investigate the performance of various machine learning algorithms in predicting key macroeconomic indicators. Our analysis covers traditional econometric models alongside modern ML approaches including random forests, gradient boosting, and neural networks. Using a comprehensive dataset spanning 1970-2023, we demonstrate that ensemble methods combining traditional and ML approaches yield superior out-of-sample forecasting performance. The results suggest that incorporating non-linear relationships and high-dimensional interactions can significantly improve prediction accuracy for GDP growth, inflation, and unemployment rates.

</details>

<details>
<summary>🔧 <strong>Technical Details</strong></summary>

**Data Sources:**
- Federal Reserve Economic Data (FRED)
- Bureau of Economic Analysis
- Bureau of Labor Statistics

**Methods:**
- Random Forest Regression
- Gradient Boosted Trees (XGBoost)
- LSTM Neural Networks
- Vector Autoregression (VAR) baselines

**Software:** Python (scikit-learn, XGBoost, TensorFlow), R (vars, forecast packages)

</details>

[Download paper](https://doi.org/10.1002/jae.example){: .btn .btn--primary}
```

This approach keeps the main pages clean while providing detailed information for interested readers.