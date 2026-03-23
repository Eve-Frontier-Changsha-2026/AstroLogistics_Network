import type { ReactNode } from 'react';

interface PanelProps {
  title?: string;
  children: ReactNode;
  className?: string;
}

export function Panel({ title, children, className = '' }: PanelProps) {
  return (
    <div
      className={`rounded-xl border p-5 backdrop-blur-sm ${className}`}
      style={{ background: 'var(--color-bg-panel)', borderColor: 'var(--color-border)' }}
    >
      {title && (
        <h3 className="text-sm font-semibold uppercase tracking-wider text-gray-400 mb-3"
            style={{ fontFamily: 'var(--font-display)' }}>
          {title}
        </h3>
      )}
      {children}
    </div>
  );
}
