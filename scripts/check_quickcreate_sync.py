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


if __name__ == "__main__":
    main()
