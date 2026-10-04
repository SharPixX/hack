#!/usr/bin/env python3
"""Convert CustomResourceDefinitions (YAML on stdin) into JSON schemas for kubeconform.

Output layout matches the kubeconform schema-location template
    <out>/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json
Schemas are made strict (additionalProperties: false) except where the CRD
explicitly allows unknown fields, so typos in our manifests fail CI.

    helm show crds <chart> | python3 tools/crd2schema.py schemas/
"""
import json
import pathlib
import sys

import yaml

# Some CRDs (prometheus-operator) contain a bare "=" enum value, which PyYAML
# would otherwise parse as the special 'value' tag.
yaml.SafeLoader.add_constructor("tag:yaml.org,2002:value", yaml.SafeLoader.construct_yaml_str)


def strict(node):
    if isinstance(node, dict):
        if node.get("type") == "object" and "properties" in node \
                and not node.get("x-kubernetes-preserve-unknown-fields") \
                and "additionalProperties" not in node:
            node["additionalProperties"] = False
        for value in node.values():
            strict(value)
    elif isinstance(node, list):
        for item in node:
            strict(item)
    return node


def main():
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "schemas")
    count = 0
    for doc in yaml.safe_load_all(sys.stdin):
        if not isinstance(doc, dict) or doc.get("kind") != "CustomResourceDefinition":
            continue
        spec = doc["spec"]
        group, kind = spec["group"], spec["names"]["kind"].lower()
        for version in spec.get("versions", []):
            schema = (version.get("schema") or {}).get("openAPIV3Schema")
            if not schema:
                continue
            target = out / group / f"{kind}_{version['name']}.json"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(strict(schema), indent=1), encoding="utf-8")
            count += 1
    print(f"crd2schema: wrote {count} schemas to {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
