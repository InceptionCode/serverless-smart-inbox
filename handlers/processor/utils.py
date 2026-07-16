"""
Shared Lambda utilities.

Keep this file identical to handlers/read_api/utils.py.
"""

from decimal import Decimal


def decimals_to_float(obj: object) -> object:
    """
    Recursively convert Decimal → float so json.dumps can serialize.

    DynamoDB stores numbers as Decimal (exact precision). json.dumps raises
    TypeError on Decimal. This walks the full object graph so nested dicts
    (e.g. the 'scores' sub-object) are also converted.

    Why float and not int? Confidence scores are fractional (e.g. 0.9987).
    int() would truncate them to 0 or 1.
    """
    if isinstance(obj, Decimal):
        return float(obj)
    if isinstance(obj, dict):
        return {k: decimals_to_float(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [decimals_to_float(v) for v in obj]
    return obj
