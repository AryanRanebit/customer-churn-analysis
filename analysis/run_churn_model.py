#!/usr/bin/env python3
"""Churn modeling layer: turns the SQL findings into a predictive baseline.

Reads the bundled IBM telco CSV and compares three models against a
majority-class baseline, with honest measurement discipline:

  * Stratified 60/20/20 train/validation/test split (seed fixed).
    Class imbalance is 26.5% churn, so accuracy alone is misleading -
    a predict-nobody-leaves model already scores ~73.5%.
  * All preprocessing lives INSIDE the sklearn Pipeline, so imputation,
    encoding, and scaling are fit on training folds only. Nothing fitted
    on the validation or test rows leaks into the features.
  * Model selection happens on the validation split; the test split is
    reserved for reporting, and every model's test metrics are reported
    transparently, not only the selected model's. A random split on a
    retrospective snapshot measures interpolation, not prospective
    performance, and columns like contract, tenure and charges may be
    recorded at or near the moment of churn (outcome-proximate), so a
    deployment would need point-in-time features. This dataset is
    fictional anyway.

Outputs: analysis/model_results.json plus charts in analysis/figures/.

Run from the repository root:  python3 analysis/run_churn_model.py
Requires: pandas, numpy, scikit-learn, matplotlib.
"""

import json
import os

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (accuracy_score, confusion_matrix,
                             precision_score, recall_score, roc_auc_score,
                             roc_curve)
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.tree import DecisionTreeClassifier

SEED = 42
CSV = 'data/raw/telco-customer-churn.csv'
FIGDIR = 'analysis/figures'

df = pd.read_csv(CSV)
df['TotalCharges'] = pd.to_numeric(df['TotalCharges'], errors='coerce')
y = (df['Churn'] == 'Yes').astype(int)
X = df.drop(columns=['Churn', 'customerID'])

numeric = ['tenure', 'MonthlyCharges', 'TotalCharges']
categorical = [c for c in X.columns if c not in numeric]

# TotalCharges is missing for exactly the 11 recorded-tenure-0 customers
# (verified by sql/03_data_quality.sql). Median imputation is fit on the
# training fold only, inside the pipeline.
preprocess = ColumnTransformer([
    ('num', Pipeline([
        ('impute', SimpleImputer(strategy='median')),
        ('scale', StandardScaler()),
    ]), numeric),
    ('cat', OneHotEncoder(handle_unknown='ignore'), categorical),
])

# 60/20/20 stratified split: compare models on validation, report on test.
X_tr, X_tmp, y_tr, y_tmp = train_test_split(
    X, y, test_size=0.4, stratify=y, random_state=SEED)
X_val, X_te, y_val, y_te = train_test_split(
    X_tmp, y_tmp, test_size=0.5, stratify=y_tmp, random_state=SEED)

models = {
    'baseline_majority': DummyClassifier(strategy='most_frequent'),
    'logistic_regression': LogisticRegression(max_iter=2000,
                                              random_state=SEED),
    'decision_tree': DecisionTreeClassifier(max_depth=6, min_samples_leaf=50,
                                            random_state=SEED),
    'random_forest': RandomForestClassifier(n_estimators=300, max_depth=10,
                                            min_samples_leaf=20,
                                            n_jobs=-1, random_state=SEED),
}


def scores(name, pipe, Xs, ys):
    pred = pipe.predict(Xs)
    proba = (pipe.predict_proba(Xs)[:, 1] if hasattr(pipe, 'predict_proba')
             else pred.astype(float))
    return {
        'model': name,
        'accuracy': round(accuracy_score(ys, pred), 4),
        'precision': round(precision_score(ys, pred, zero_division=0), 4),
        'recall': round(recall_score(ys, pred, zero_division=0), 4),
        'roc_auc': round(roc_auc_score(ys, proba), 4),
    }


fitted = {}
val_rows, test_rows = [], []
for name, model in models.items():
    pipe = Pipeline([('prep', preprocess), ('model', model)])
    pipe.fit(X_tr, y_tr)
    fitted[name] = pipe
    val_rows.append(scores(name, pipe, X_val, y_val))
    test_rows.append(scores(name, pipe, X_te, y_te))

val_df = pd.DataFrame(val_rows)
test_df = pd.DataFrame(test_rows)
print('== validation (model comparison) ==')
print(val_df.to_string(index=False))
print('== test (reported numbers, all models shown) ==')
print(test_df.to_string(index=False))

# Final model: best validation ROC-AUC among the three real models.
candidates = val_df[val_df.model != 'baseline_majority']
best = candidates.loc[candidates.roc_auc.idxmax(), 'model']
best_pipe = fitted[best]
print(f'selected on validation: {best}')

os.makedirs(FIGDIR, exist_ok=True)

# Confusion matrix on test.
cm = confusion_matrix(y_te, best_pipe.predict(X_te))
fig, ax = plt.subplots(figsize=(4.2, 3.6))
im = ax.imshow(cm, cmap='Blues')
ax.set_xticks([0, 1], ['stayed', 'churned'])
ax.set_yticks([0, 1], ['stayed', 'churned'])
ax.set_xlabel('predicted'); ax.set_ylabel('actual')
ax.set_title(f'Confusion matrix (test)\n{best}', fontsize=10)
for (i, j), v in np.ndenumerate(cm):
    ax.text(j, i, str(v), ha='center', va='center',
            color='white' if v > cm.max() / 2 else 'black')
fig.tight_layout()
fig.savefig(f'{FIGDIR}/confusion_matrix.png', dpi=150)
plt.close(fig)

# ROC curves on test.
fig, ax = plt.subplots(figsize=(5, 4.2))
for name in ['logistic_regression', 'decision_tree', 'random_forest']:
    proba = fitted[name].predict_proba(X_te)[:, 1]
    fpr, tpr, _ = roc_curve(y_te, proba)
    ax.plot(fpr, tpr, label=f"{name} (AUC {roc_auc_score(y_te, proba):.3f})")
ax.plot([0, 1], [0, 1], 'k--', linewidth=0.8, label='random')
ax.set_xlabel('false positive rate'); ax.set_ylabel('true positive rate')
ax.set_title('ROC curves (test split)')
ax.legend(fontsize=8)
fig.tight_layout()
fig.savefig(f'{FIGDIR}/roc_curves.png', dpi=150)
plt.close(fig)

# Feature importance on test-selected model where available.
rf = fitted['random_forest']
names = (list(numeric)
         + list(rf.named_steps['prep']
                .named_transformers_['cat']
                .get_feature_names_out(categorical)))
imp = pd.Series(rf.named_steps['model'].feature_importances_,
                index=names).sort_values(ascending=False).head(15)
fig, ax = plt.subplots(figsize=(6, 4.5))
imp.sort_values().plot.barh(ax=ax, color='#346888')
ax.set_title('Random forest feature importance (top 15)')
ax.set_xlabel('mean decrease in impurity')
fig.tight_layout()
fig.savefig(f'{FIGDIR}/feature_importance.png', dpi=150)
plt.close(fig)

out = {
    'seed': SEED,
    'split': {'train': len(X_tr), 'validation': len(X_val), 'test': len(X_te)},
    'churn_rate_overall': round(float(y.mean()), 4),
    'validation': val_rows,
    'test': test_rows,
    'selected_model': best,
    'note': ('Stratified random split on a fictional snapshot sample; '
             'measures interpolation, not prospective performance. '
             'Preprocessing fit on the training fold only. Columns such as '
             'contract, tenure and charges may be outcome-proximate; a real '
             'deployment needs point-in-time features. Validation used for '
             'selection, test reported for all models.'),
}
with open('analysis/model_results.json', 'w') as f:
    json.dump(out, f, indent=2)
print('saved analysis/model_results.json and analysis/figures/*.png')
