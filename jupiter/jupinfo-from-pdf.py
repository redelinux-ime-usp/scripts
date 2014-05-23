#!/bin/env python
# -*- coding: utf-8 -*-

from __future__ import print_function

import sys
import re
import codecs

from collections import namedtuple
from distutils.spawn import find_executable
from subprocess import check_output

from pprint import pformat

if not hasattr(__builtins__, 'callable'):
    def callable(obj):
        return hasattr(obj, '__call__')

###

class CourseMapping(namedtuple('CourseMapping', 'code suffix course')):
    _mappings = None

    night_period_code = 4

    @classmethod
    def suffix_is_nightly(cls, suffix):
        return suffix % cls.night_period_code == 0

    @classmethod
    def mappings(cls):
        if cls._mappings is None:
            cls._mappings = map(lambda m: cls(*m), [
                (45061, None, 'be'),
                (45051, None, 'bcc'),
                (45040, None, 'bma'),
                (45042, None, 'bma'),
                (45070, None, 'bmac'),
                (45031, None, 'bm'),
                (lambda c: c in (45023, 45024), cls.suffix_is_nightly, 'licn'),
                (lambda c: c in (45023, 45024), None, 'lic')
            ])

            print(pformat(cls._mappings), file=sys.stderr)

        return cls._mappings

    @classmethod
    def _compare_component(cls, matcher, value):
        if callable(matcher):
            return bool(matcher(value))
        elif matcher is None:
            return True
        else:
            return value == matcher

    @classmethod
    def match(cls, code):
        code, suffix = code
        for mp in cls.mappings():
            if not cls._compare_component(mp.code, code):
                continue
            if not cls._compare_component(mp.suffix, suffix):
                continue
            
            return unicode(mp.course)

        return None

class Person(namedtuple('Person', 'num nusp course_code status ingress name')):
    match_re =re.compile(
        r'^(?P<num>\d+)\s+'
        r'(?:(?P<status>\*+)\s+)?'
        r'(?P<nusp>\d+)\s+'
        r'(?P<course>\d+/\d+)\s+'
        r'(?P<ingress>\d+/\d+)\s+'
        r'(?P<name>.+)$'
    )

    class Status(object):
        """Matrícula regular"""
        REGULAR = 0

        """Curso trancado"""
        ON_BREAK = 1
        
        """Não matriculado"""
        NOT_ENROLLED = 2
    
        """cursando disciplina no Exterior,ou outras IES do Brasil, ou Atividades
           de Cultura e Extensão"""
        AWAY = 3

        @classmethod
        def from_pattern(cls, pattern):
            if not pattern:
                return cls.REGULAR
            elif pattern == '*':
                return cls.ON_BREAK
            elif pattern == '**':
                return cls.NOT_ENROLLED
            elif pattern == '***':
                return cls.AWAY
            else:
                raise ValueError("Unknown course status pattern '{0}'".format(pattern))
    
    @classmethod
    def from_line(cls, line):
        m = cls.match_re.match(line)
        if not m:
            return None

        num = int(m.group('num'))
        status = cls.Status.from_pattern(m.group('status'))

        nusp = int(m.group('nusp'))
        course_code = tuple(map(int, m.group('course').split('/')))
        ingress = tuple(map(int, m.group('ingress').split('/')))
        name = m.group('name').strip()

        return cls(num=num, nusp=nusp, course_code=course_code, status=status,
                   ingress=ingress, name=name)

    def course_name(self):
        return CourseMapping.match(self.course_code)

    def _jup_info_ingress(self):
        return u'%02d-%02d-%02d' % (self.ingress[0], self.ingress[1], 1)

    def jup_info_line(self):
        return ":".join(map(unicode, (self.nusp, self.name, self.course_name(),
                                      self._jup_info_ingress())))

###

pdftotext = find_executable('pdftotext')
if not pdftotext:
    print("Erro: programa pdftotext não encontrado", file=sys.stderr)
    sys.exit(1)

if len(sys.argv) < 2:
    print("Uso: {0} pdf_entrada [txt_saida]", file=sys.stderr)
    sys.exit(1)

in_file = sys.argv[1]
if len(sys.argv) > 2:
    out_file = open(sys.argv[2], 'w')
else:
    out_file = sys.stdout

text_content = check_output([pdftotext, '-layout', in_file, '-'])
text_content = unicode(text_content, 'utf_8')

if sys.stdout.encoding != 'UTF-8':
    sys.stdout = codecs.getwriter('utf_8')(sys.stdout)

people = []
for line in text_content.split('\n'):
    person = Person.from_line(line)
    if person:
        people.append(person)
        print(person.jup_info_line())