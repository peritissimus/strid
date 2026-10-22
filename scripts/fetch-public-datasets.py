#!/usr/bin/env python3
"""Download publicly available synthetic Indian ID & bank-statement datasets for Strid evaluation.

Sources (all 100% synthetic, publicly hosted on Hugging Face):
  1. vk9199/aixbitss-aadhaar-synthetic
     Synthetic Aadhaar card image with Hindi/English labels, DOB, QR code and Verhoeff-valid UID.
  2. whoismatz/pan-card-ocr-synthetic
     Synthetic Income Tax Department PAN card image with holder name, father's name, DOB and PAN.
  3. AgamiAI/Indian-Bank-Statements (Apache-2.0)
     Synthetic Indian business bank statement PDF + companion ground-truth JSON (account number,
     IFSC, MICR, CIF/customer ID, postal PIN code, and 160+ NEFT/RTGS/IMPS/UPI transactions).
  4. adwaith06/indic-synthetic-profiles
     indic-faker profiles with Verhoeff-validated Aadhaar, PAN, IFSC, bank account, UPI VPA,
     +91 mobile number, email, date of birth, address and PIN code.
  5. somukandula/maskara-indian-pii-200k
     Annotated Indian PII benchmark spans covering Passport, Vehicle Registration, Luhn-valid
     Credit Cards, Aadhaar, PAN, UPI ID, Phone, Email, Date of Birth and Person names.

Usage:
  python3 scripts/fetch-public-datasets.py [output_dir]
  # Default output_dir: ios/StridKit/Eval/public
  # Evaluate with:
  strid eval ios/StridKit/Eval/public --verbose
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
import urllib.request


def write_expected(
    path: pathlib.Path,
    entities: list[tuple[str | None, str]],
    not_texts: list[str],
) -> None:
    payload = {
        "entities": [
            ({"type": t, "text": v} if t is not None else {"text": v})
            for t, v in entities
        ],
        "not": [{"text": s} for s in not_texts],
    }
    path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def fetch_all(out_dir: pathlib.Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. vk9199/aixbitss-aadhaar-synthetic
    print("Fetching vk9199/aixbitss-aadhaar-synthetic -> hf_aadhaar_card.jpg ...")
    urllib.request.urlretrieve(
        "https://huggingface.co/datasets/vk9199/aixbitss-aadhaar-synthetic/resolve/main/10front_scaled_up.jpg",
        out_dir / "hf_aadhaar_card.jpg",
    )
    write_expected(
        out_dir / "hf_aadhaar_card.expected.json",
        [
            ("PERSON", "Rudra"),
            ("IN_DOB", "05-03-1993"),
            ("IN_AADHAAR", "9876 5432 1008"),
            ("BARCODE", "QR / barcode"),
        ],
        ["Male"],
    )

    # 2. whoismatz/pan-card-ocr-synthetic
    print("Fetching whoismatz/pan-card-ocr-synthetic -> hf_pan_card.jpg ...")
    pan_meta_url = (
        "https://datasets-server.huggingface.co/rows?"
        "dataset=whoismatz%2Fpan-card-ocr-synthetic&config=default&split=train&offset=0&length=1"
    )
    pan_rows = json.loads(urllib.request.urlopen(pan_meta_url).read().decode())["rows"]
    pan_img_url = pan_rows[0]["row"]["image"]["src"]
    urllib.request.urlretrieve(pan_img_url, out_dir / "hf_pan_card.jpg")
    write_expected(
        out_dir / "hf_pan_card.expected.json",
        [
            ("PERSON", "MANOJ DESAL"),
            ("PERSON", "NEHA AGARWAL"),
            ("IN_DOB", "03/11/2003"),
            ("IN_PAN", "DDGAH3295Y"),
        ],
        ["INCOME TAX DEPARTMENT", "Permanent Account Number Card"],
    )

    # 3. AgamiAI/Indian-Bank-Statements
    print("Fetching AgamiAI/Indian-Bank-Statements -> agami_bank_statement.pdf ...")
    urllib.request.urlretrieve(
        "https://huggingface.co/datasets/AgamiAI/Indian-Bank-Statements/resolve/main/train/India_Bank_Statement_Digital_Type1/00001.pdf",
        out_dir / "agami_bank_statement.pdf",
    )
    agami_json = json.loads(
        urllib.request.urlopen(
            "https://huggingface.co/datasets/AgamiAI/Indian-Bank-Statements/resolve/main/train/India_Bank_Statement_Digital_Type1/00001.json"
        )
        .read()
        .decode()
    )
    agami_entities: list[tuple[str | None, str]] = [
        ("PERSON", agami_json["account_holder"]),
        ("IN_BANK_ACCOUNT", agami_json["account_number"]),
        ("IN_IFSC", agami_json["ifsc_code"]),
        ("IN_MICR", agami_json["micr_code"]),
        ("IN_CUSTOMER_ID", agami_json["customer_id"]),
        ("IN_PIN_CODE", "702820"),
        ("LOCATION", "Alipore"),
        ("LOCATION", "Kolkata"),
        ("LOCATION", "West Bengal"),
    ]
    seen_agami: set[tuple[str | None, str]] = set(agami_entities)
    for txn in agami_json["transactions"]:
        desc = txn["description"]
        for ref in re.findall(r"\d{12}", desc):
            item = ("IN_TXN_REF", ref)
            if item not in seen_agami:
                seen_agami.add(item)
                agami_entities.append(item)
        for ifsc in re.findall(r"\b[A-Z]{4}0[A-Z0-9]{6}\b", desc):
            item = ("IN_IFSC", ifsc)
            if item not in seen_agami:
                seen_agami.add(item)
                agami_entities.append(item)
        for phone in re.findall(r"(?:TRANSFER (?:TO|FROM) )([6-9]\d{9})\b", desc):
            item = ("PHONE", phone)
            if item not in seen_agami:
                seen_agami.add(item)
                agami_entities.append(item)

    write_expected(
        out_dir / "agami_bank_statement.expected.json",
        agami_entities,
        ["CURRENT ACCOUNT", "Closing Balance", "Opening Balance"],
    )

    # 4. adwaith06/indic-synthetic-profiles
    print("Fetching adwaith06/indic-synthetic-profiles -> indic_kyc_profiles.txt ...")
    indic_url = (
        "https://datasets-server.huggingface.co/rows?"
        "dataset=adwaith06%2Findic-synthetic-profiles&config=default&split=train&offset=0&length=5"
    )
    indic_rows = json.loads(urllib.request.urlopen(indic_url).read().decode())["rows"]
    selected_indic = [indic_rows[0]["row"], indic_rows[2]["row"], indic_rows[3]["row"]]
    lines = [
        "KYC CUSTOMER VERIFICATION STATEMENT (SOURCE: adwaith06/indic-synthetic-profiles)",
        "================================================================================",
        "",
    ]
    indic_expected: list[tuple[str | None, str]] = []
    for idx, r in enumerate(selected_indic, start=1):
        addr_pin = re.search(r"\b([1-9]\d{5})\b", r["address"])
        lines.extend(
            [
                f"Record #{idx}",
                f"Customer Name: {r['name']} ({r['name_native']})",
                f"DOB: {r['dob']}   Gender: {r['gender'].title()}",
                f"Aadhaar No: {r['aadhaar']}   PAN: {r['pan']}",
                f"Mobile: {r['phone']}   Email: {r['email']}",
                f"Bank: {r['bank_account_bank']}   Account No: {r['bank_account_account']}   IFSC: {r['bank_account_ifsc']}",
                f"UPI ID: {r['upi_id']}",
                f"Address: {r['address']}",
                f"City: {r['city']}, {r['state']} - Pincode: {r['pincode']}",
                "",
            ]
        )
        indic_expected.extend(
            [
                ("PERSON", r["name"]),
                ("IN_DOB", r["dob"]),
                ("IN_AADHAAR", r["aadhaar"]),
                ("IN_PAN", r["pan"]),
                ("PHONE", r["phone"]),
                ("EMAIL", r["email"]),
                ("IN_BANK_ACCOUNT", str(r["bank_account_account"])),
                ("IN_IFSC", r["bank_account_ifsc"]),
                ("IN_UPI_ID", r["upi_id"]),
                ("ADDRESS", r["address"].split(" - ")[0]),
                ("IN_PIN_CODE", str(r["pincode"])),
                ("LOCATION", r["state"]),
            ]
        )
        if addr_pin:
            indic_expected.append(("IN_PIN_CODE", addr_pin.group(1)))

    (out_dir / "indic_kyc_profiles.txt").write_text("\n".join(lines), encoding="utf-8")
    write_expected(
        out_dir / "indic_kyc_profiles.expected.json",
        indic_expected,
        ["KYC CUSTOMER VERIFICATION STATEMENT", "Record #1", "Gender"],
    )

    # 5. somukandula/maskara-indian-pii-200k
    print("Fetching somukandula/maskara-indian-pii-200k -> maskara_indian_pii.txt ...")
    by_idx: dict[int, dict] = {}
    for offset in (0, 100, 200):
        maskara_url = (
            f"https://datasets-server.huggingface.co/rows?"
            f"dataset=somukandula%2Fmaskara-indian-pii-200k&config=default&split=train&offset={offset}&length=100"
        )
        rows = json.loads(urllib.request.urlopen(maskara_url).read().decode())["rows"]
        for r in rows:
            by_idx[r["row_idx"]] = r["row"]

    chosen_indices = [1, 4, 9, 58, 63, 85, 91, 155, 172, 281]
    maskara_lines = [
        "PUBLIC BENCHMARK SAMPLES (somukandula/maskara-indian-pii-200k)",
        "",
    ]
    label_map = {
        "PERSON_NAME": "PERSON",
        "PHONE": "PHONE",
        "EMAIL": "EMAIL",
        "UPI_ID": "IN_UPI_ID",
        "VEHICLE_REG": "IN_VEHICLE_REG",
        "CREDIT_CARD": "CREDIT_CARD",
        "PASSPORT": "IN_PASSPORT",
        "PAN_CARD": "IN_PAN",
        "DATE_OF_BIRTH": "IN_DOB",
        "AADHAAR": "IN_AADHAAR",
    }
    maskara_expected: list[tuple[str | None, str]] = []
    for i in chosen_indices:
        row = by_idx[i]
        maskara_lines.append(row["text"])
        maskara_lines.append("")
        for ent in row["entities"]:
            val = row["text"][ent["start"] : ent["end"]]
            mapped = label_map.get(ent["label"])
            if mapped:
                maskara_expected.append((mapped, val))

    (out_dir / "maskara_indian_pii.txt").write_text("\n".join(maskara_lines), encoding="utf-8")
    write_expected(
        out_dir / "maskara_indian_pii.expected.json",
        maskara_expected,
        ["PUBLIC BENCHMARK SAMPLES"],
    )

    print(f"Done. Wrote 5 public dataset fixtures and .expected.json files to {out_dir}")


if __name__ == "__main__":
    repo_root = pathlib.Path(__file__).resolve().parent.parent
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else repo_root / "ios" / "StridKit" / "Eval" / "public"
    fetch_all(target)
