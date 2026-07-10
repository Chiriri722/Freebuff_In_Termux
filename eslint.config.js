import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  // 글로벌 무시
  {
    ignores: ['dist/', 'node_modules/', 'coverage/'],
  },

  // 기본 추천 규칙
  js.configs.recommended,
  ...tseslint.configs.recommended,

  // 프로젝트 소스 및 테스트 파일
  {
    files: ['src/**/*.ts', 'tests/**/*.ts'],
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: 'module',
    },
    rules: {
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_' },
      ],
      '@typescript-eslint/no-explicit-any': 'warn',
      'no-console': 'off',
      'prefer-const': 'error',
    },
  },

  // 테스트 파일 완화
  {
    files: ['tests/**/*.ts'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
    },
  },
);
