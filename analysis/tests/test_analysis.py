"""Regression tests for the Python analysis layer.

The SQL side of this project already has a hard-failing battery
(sql/07_regression_tests.sql). This suite gives the Python side the same
protection:

  * the bundled IBM CSV still has the exact shape every finding depends on;
  * every query in analysis/run_analysis.py recomputes to the committed
    analysis/results.json, so code and published numbers cannot drift apart;
  * analysis/model_results.json is internally consistent (split sizes,
    baseline behavior, selection rule, metric ranges);
  * if scikit-learn is installed, analysis/run_churn_model.py reproduces the
    committed model metrics and figures end to end in a temporary directory
    (auto-skipped otherwise).

Run from anywhere:  python3 -m pytest analysis/tests -v
Core tests need only the standard library.
"""

import csv
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'analysis'))

import run_analysis as ra

CSV = ROOT / 'data' / 'raw' / 'telco-customer-churn.csv'
RESULTS = ROOT / 'analysis' / 'results.json'
MODEL_RESULTS = ROOT / 'analysis' / 'model_results.json'
FIGURES = ROOT / 'analysis' / 'figures'
MODELS = ['baseline_majority', 'logistic_regression', 'decision_tree',
          'random_forest']


@pytest.fixture(scope='module')
def committed():
    return json.loads(RESULTS.read_text())


@pytest.fixture(scope='module')
def recomputed():
    return ra.run_queries(ra.build_db())


@pytest.fixture(scope='module')
def model_results():
    return json.loads(MODEL_RESULTS.read_text())


# --- raw data integrity -------------------------------------------------

def test_csv_shape_and_labels():
    with open(CSV, newline='') as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == 7043
    assert len(rows[0]) == 21
    ids = [r['customerID'] for r in rows]
    assert len(set(ids)) == 7043, 'customer IDs must be unique'
    assert {r['Churn'] for r in rows} == {'Yes', 'No'}
    blank_total = [r for r in rows if not r['TotalCharges'].strip()]
    assert len(blank_total) == 11
    assert all(int(r['tenure']) == 0 for r in blank_total)


# --- analysis layer: code and committed numbers cannot drift ------------

def test_query_set_matches_committed_results(committed, recomputed):
    assert set(recomputed) == set(committed)
    assert len(recomputed) == 21  # 9 descriptive (Q1-Q9) + 12 insight (I1-I11, I10b)


def test_every_query_recomputes_to_committed_results(committed, recomputed):
    for name in committed:
        assert recomputed[name] == committed[name], (
            f'{name}: run_analysis.py no longer reproduces results.json')


def test_headline_numbers(committed):
    overall = committed['Q1_overall'][0]
    assert (overall['customers'], overall['churned'], overall['churn_pct']) == \
        (7043, 1869, 26.5)
    revenue = committed['Q9_revenue'][0]
    assert revenue['monthly_revenue_from_churned'] == 139130.85
    assert revenue['churned_customers'] == 1869


# --- model results: internal consistency --------------------------------

def test_model_split_sizes(model_results):
    split = model_results['split']
    assert split['train'] + split['validation'] + split['test'] == 7043
    assert split['validation'] == split['test']
    assert model_results['churn_rate_overall'] == 0.2654
    assert model_results['seed'] == 42


def test_model_selection_rule_and_baseline(model_results):
    for stage in ('validation', 'test'):
        rows = model_results[stage]
        assert [r['model'] for r in rows] == MODELS
        for r in rows:
            for metric in ('accuracy', 'precision', 'recall', 'roc_auc'):
                assert 0.0 <= r[metric] <= 1.0
    baseline = model_results['test'][0]
    assert baseline['roc_auc'] == 0.5
    assert baseline['recall'] == 0.0
    candidates = [r for r in model_results['validation']
                  if r['model'] != 'baseline_majority']
    best = max(candidates, key=lambda r: r['roc_auc'])
    assert model_results['selected_model'] == best['model']


def test_figures_present_and_valid():
    for name in ('confusion_matrix.png', 'roc_curves.png',
                 'feature_importance.png'):
        blob = (FIGURES / name).read_bytes()
        assert blob[:8] == b'\x89PNG\r\n\x1a\n', name
        assert len(blob) > 10_000, f'{name} looks truncated'


# --- end-to-end model reproduction (needs sklearn) ----------------------

@pytest.mark.skipif(importlib.util.find_spec('sklearn') is None,
                    reason='scikit-learn not installed')
def test_model_pipeline_reproduces_committed_metrics(tmp_path,
                                                     model_results):
    """Run run_churn_model.py in a clean copy and require identical output."""
    (tmp_path / 'data' / 'raw').mkdir(parents=True)
    shutil.copy(CSV, tmp_path / 'data' / 'raw' / CSV.name)
    (tmp_path / 'analysis').mkdir()
    shutil.copy(ROOT / 'analysis' / 'run_churn_model.py',
                tmp_path / 'analysis' / 'run_churn_model.py')
    subprocess.run([sys.executable, 'analysis/run_churn_model.py'],
                   cwd=tmp_path, check=True, capture_output=True, text=True)
    fresh = json.loads(
        (tmp_path / 'analysis' / 'model_results.json').read_text())
    assert fresh == model_results
    for name in ('confusion_matrix.png', 'roc_curves.png',
                 'feature_importance.png'):
        assert (tmp_path / 'analysis' / 'figures' / name).stat().st_size > 10_000
