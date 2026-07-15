#!/usr/bin/env python3
"""Fail CI when the Lambda code inlined in template-quickcreate.yaml drifts
from the canonical source in backend/src/presign/app.py."""

import sys

import yaml


class CfnLoader(yaml.SafeLoader):
    """SafeLoader that tolerates CloudFormation short tags (!Ref, !Sub, ...)."""


def _ignore_tag(loader, tag_suffix, node):
    if isinstance(node, yaml.ScalarNode):
        return loader.construct_scalar(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    return loader.construct_mapping(node)


CfnLoader.add_multi_constructor("!", _ignore_tag)


def main():
    with open("backend/template-quickcreate.yaml") as f:
        template = yaml.load(f, Loader=CfnLoader)
    inline = template["Resources"]["PresignFunction"]["Properties"]["InlineCode"]

    with open("backend/src/presign/app.py") as f:
        source = f.read()

    if inline.strip() != source.strip():
        sys.exit(
            "backend/template-quickcreate.yaml の InlineCode が "
            "backend/src/presign/app.py と一致していません。"
            "app.py を変更したら InlineCode にも同じ内容を反映してください。"
        )
    print("quick-create template InlineCode is in sync with app.py")

    # docs/ copy is served by GitHub Pages as a durable fallback in case the
    # distributor's S3 bucket (the quick-create link's source) disappears.
    with open("backend/template-quickcreate.yaml") as f:
        canonical = f.read()
    with open("docs/template-quickcreate.yaml") as f:
        pages_copy = f.read()
    if canonical != pages_copy:
        sys.exit(
            "docs/template-quickcreate.yaml が backend/template-quickcreate.yaml "
            "と一致していません。backend 側を変更したら docs 側へコピーしてください"
            "(cp backend/template-quickcreate.yaml docs/)。"
        )
    print("docs/ copy of the quick-create template is in sync")


if __name__ == "__main__":
    main()
