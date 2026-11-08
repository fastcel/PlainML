from pathlib import Path
import sys

import numpy as np
import pandas as pd

from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    confusion_matrix,
)
from sklearn.model_selection import train_test_split
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import StandardScaler


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

if len(sys.argv) != 2:
    print(
        "Usage: python tools/train_student_model.py "
        "data/student-performance/student/student-por.csv"
    )
    sys.exit(1)

DATASET_PATH = Path(sys.argv[1])

if not DATASET_PATH.exists():
    print(f"Dataset not found: {DATASET_PATH}")
    sys.exit(1)

OUTPUT_PATH = Path("examples/pretrained_student_success.plain")

# UCI columns used by the model.
FEATURES = [
    "G1",
    "G2",
    "studytime",
    "failures",
    "absences",
    "higher",
    "schoolsup",
    "famsup",
]

# Human-readable PlainML names.
PLAIN_NAMES = {
    "G1": "first_grade",
    "G2": "second_grade",
    "studytime": "study_time",
    "failures": "past_failures",
    "absences": "absences",
    "higher": "wants_higher_education",
    "schoolsup": "school_support",
    "famsup": "family_support",
}


# ------------------------------------------------------------
# Load dataset
# ------------------------------------------------------------

# sep=None lets pandas detect the delimiter used by the UCI CSV.
df = pd.read_csv(
    DATASET_PATH,
    sep=None,
    engine="python",
)

required_columns = set(FEATURES + ["G3"])

missing = required_columns - set(df.columns)

if missing:
    print("Dataset is missing required columns:")
    for name in sorted(missing):
        print(f"  {name}")
    sys.exit(1)


# ------------------------------------------------------------
# Prepare features
# ------------------------------------------------------------

data = df[FEATURES].copy()

# Convert yes/no values to 1/0.
for column in ["higher", "schoolsup", "famsup"]:
    data[column] = (
        data[column]
        .astype(str)
        .str.lower()
        .map({"yes": 1.0, "no": 0.0})
    )

# Make all features floating-point.
X = data.astype(float).to_numpy()

# Portuguese grades are from 0 to 20.
#
# For this demonstration:
#
# success = 1  when G3 >= 10
# success = 0  when G3 < 10
#
# G3 itself is NEVER supplied as an input to the model.
y = (df["G3"].astype(float).to_numpy() >= 10.0).astype(int)


# ------------------------------------------------------------
# Train/test split
# ------------------------------------------------------------

indices = np.arange(len(df))

(
    X_train,
    X_test,
    y_train,
    y_test,
    idx_train,
    idx_test,
) = train_test_split(
    X,
    y,
    indices,
    test_size=0.25,
    random_state=42,
    stratify=y,
)


# ------------------------------------------------------------
# Normalize training features
# ------------------------------------------------------------

scaler = StandardScaler()

X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)


# ------------------------------------------------------------
# Balance the TRAINING data only
# ------------------------------------------------------------
#
# The dataset contains substantially more passing students than
# failing students. We oversample the minority training class so
# that the network does not learn to simply predict "success"
# for almost everybody.
#
# The held-out test set is NOT modified.

rng = np.random.default_rng(42)

class_zero = np.where(y_train == 0)[0]
class_one = np.where(y_train == 1)[0]

if len(class_zero) < len(class_one):
    minority = class_zero
    majority = class_one
else:
    minority = class_one
    majority = class_zero

extra = rng.choice(
    minority,
    size=len(majority) - len(minority),
    replace=True,
)

balanced_indices = np.concatenate(
    [np.arange(len(y_train)), extra]
)

rng.shuffle(balanced_indices)

X_train_balanced = X_train_scaled[balanced_indices]
y_train_balanced = y_train[balanced_indices]


# ------------------------------------------------------------
# Train neural network
# ------------------------------------------------------------
#
# Architecture:
#
# 8 inputs
#     ->
# 6 ReLU hidden neurons
#     ->
# 1 binary output
#
# scikit-learn uses a logistic activation for its binary output.
# A logistic probability >= 0.5 is equivalent to the output
# pre-activation being >= 0.
#
# Therefore the final logistic decision can be exported exactly
# as PlainML's step activation.

model = MLPClassifier(
    hidden_layer_sizes=(6,),
    activation="relu",
    solver="lbfgs",
    alpha=0.01,
    max_iter=5000,
    random_state=42,
)

model.fit(
    X_train_balanced,
    y_train_balanced,
)


# ------------------------------------------------------------
# Evaluate held-out test data
# ------------------------------------------------------------

predictions = model.predict(X_test_scaled)

accuracy = accuracy_score(
    y_test,
    predictions,
)

balanced_accuracy = balanced_accuracy_score(
    y_test,
    predictions,
)

tn, fp, fn, tp = confusion_matrix(
    y_test,
    predictions,
    labels=[0, 1],
).ravel()

print()
print("Student success model")
print("---------------------")
print(f"Dataset rows:          {len(df)}")
print(f"Training rows:         {len(X_train)}")
print(f"Held-out test rows:    {len(X_test)}")
print()
print(f"Accuracy:              {accuracy:.4f}")
print(f"Balanced accuracy:     {balanced_accuracy:.4f}")
print()
print("Confusion matrix")
print(f"  true negative:       {tn}")
print(f"  false positive:      {fp}")
print(f"  false negative:      {fn}")
print(f"  true positive:       {tp}")


# ------------------------------------------------------------
# Extract trained parameters
# ------------------------------------------------------------

# sklearn:
#
# hidden_pre = normalized_input @ W1 + b1
# hidden     = relu(hidden_pre)
# output_pre = hidden @ W2 + b2
#
# shapes:
#
# W1 = [8, 6]
# b1 = [6]
# W2 = [6, 1]
# b2 = [1]

W1 = model.coefs_[0]
b1 = model.intercepts_[0]

W2 = model.coefs_[1][:, 0]
b2 = float(model.intercepts_[1][0])


# ------------------------------------------------------------
# Fold StandardScaler into first layer
# ------------------------------------------------------------
#
# Training uses:
#
# normalized_x = (x - mean) / scale
#
# We do NOT want PlainML users to manually normalize values.
#
# The same computation can be rewritten as:
#
# raw_weight = trained_weight / scale
#
# raw_bias =
#     trained_bias
#     - sum(mean * trained_weight / scale)
#
# This makes the exported network accept the original raw values.

raw_W1 = W1 / scaler.scale_[:, np.newaxis]

raw_b1 = (
    b1
    - (scaler.mean_ / scaler.scale_) @ W1
)


# ------------------------------------------------------------
# Verify exported mathematics
# ------------------------------------------------------------

hidden_raw = np.maximum(
    X_test @ raw_W1 + raw_b1,
    0.0,
)

output_raw = (
    hidden_raw @ W2 + b2
)

exported_predictions = (
    output_raw >= 0.0
).astype(int)

if not np.array_equal(
    exported_predictions,
    predictions,
):
    print()
    print(
        "ERROR: exported PlainML mathematics "
        "does not match sklearn."
    )
    sys.exit(1)

print()
print("Export equivalence check: PASS")


# ------------------------------------------------------------
# Choose a real held-out example for the .plain file
# ------------------------------------------------------------
#
# Pick the correctly classified held-out student with the
# strongest decision margin.

probabilities = model.predict_proba(
    X_test_scaled
)[:, 1]

correct = predictions == y_test

confidence = np.abs(
    probabilities - 0.5
)

confidence[~correct] = -1.0

demo_position = int(
    np.argmax(confidence)
)

demo_x = X_test[demo_position]
demo_original_index = idx_test[demo_position]
demo_actual_g3 = float(
    df.iloc[demo_original_index]["G3"]
)
demo_expected = int(
    y_test[demo_position]
)
demo_prediction = int(
    predictions[demo_position]
)

print()
print("Selected held-out demonstration student")
print("----------------------------------------")

for feature, value in zip(
    FEATURES,
    demo_x,
):
    print(
        f"{PLAIN_NAMES[feature]:25s} = {value:g}"
    )

print(f"{'actual_final_grade':25s} = {demo_actual_g3:g}")
print(f"{'expected_success':25s} = {demo_expected}")
print(f"{'model_prediction':25s} = {demo_prediction}")


# ------------------------------------------------------------
# Generate PlainML source
# ------------------------------------------------------------

def number(value):
    """
    PlainML currently accepts ordinary decimal numbers rather
    than scientific notation, so always emit decimal notation.
    """
    return f"{float(value):.10f}"


lines = []

lines.append("network pretrained_student_success {")
lines.append("")
lines.append("    inputs {")

for feature in FEATURES:
    lines.append(
        f"        {PLAIN_NAMES[feature]};"
    )

lines.append("    }")
lines.append("")
lines.append("    layer hidden activation relu {")
lines.append("")

hidden_count = raw_W1.shape[1]

for hidden in range(hidden_count):

    neuron_name = f"hidden_{hidden + 1}"

    lines.append(
        f"        neuron {neuron_name} {{"
    )

    for feature_index, feature in enumerate(
        FEATURES
    ):
        plain_name = PLAIN_NAMES[feature]

        weight = raw_W1[
            feature_index,
            hidden,
        ]

        lines.append(
            f"            {plain_name} "
            f"weight {number(weight)};"
        )

    lines.append(
        f"            bias "
        f"{number(raw_b1[hidden])};"
    )

    lines.append("        }")
    lines.append("")

lines.append("    }")
lines.append("")
lines.append(
    "    layer output activation step {"
)
lines.append("")
lines.append("        neuron success {")

for hidden in range(hidden_count):

    neuron_name = f"hidden_{hidden + 1}"

    lines.append(
        f"            {neuron_name} "
        f"weight {number(W2[hidden])};"
    )

lines.append(
    f"            bias {number(b2)};"
)

lines.append("        }")
lines.append("")
lines.append("    }")
lines.append("}")
lines.append("")
lines.append(
    "predict pretrained_student_success with {"
)

for feature, value in zip(
    FEATURES,
    demo_x,
):
    lines.append(
        f"    {PLAIN_NAMES[feature]} "
        f"= {number(value)};"
    )

lines.append("}")
lines.append("")

OUTPUT_PATH.write_text(
    "\n".join(lines),
    encoding="utf-8",
)

print()
print(
    f"Generated PlainML model: {OUTPUT_PATH}"
)

