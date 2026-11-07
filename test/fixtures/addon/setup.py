# Proof 2 fixture (ADR 0004): a minimal add-on that exists only in /app/data/packages once installed.
# Laid out as docassemble's Playground writes setup.py: one argument per line, because docassemble
# reads the package name back out of this file with a line-based pattern.
from setuptools import setup, find_namespace_packages

setup(name='docassemble.cloudronproof',
      version='0.0.1',
      description='Cloudron package proof add-on',
      packages=find_namespace_packages(include=['docassemble.*']),
      package_data={'docassemble.cloudronproof': ['data/questions/*.yml']},
      zip_safe=False,
      )
