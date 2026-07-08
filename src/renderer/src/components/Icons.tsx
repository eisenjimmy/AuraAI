// Minimal stroke icons (16px grid), Codex-editor style. No emoji anywhere.

interface IconProps {
  size?: number
  className?: string
}

function base(size: number): React.SVGProps<SVGSVGElement> {
  return {
    width: size,
    height: size,
    viewBox: '0 0 16 16',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.4,
    strokeLinecap: 'round',
    strokeLinejoin: 'round'
  }
}

export const GearIcon = ({ size = 14 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <circle cx="8" cy="8" r="2.2" />
    <path d="M8 1.8v2M8 12.2v2M1.8 8h2M12.2 8h2M3.6 3.6l1.4 1.4M11 11l1.4 1.4M12.4 3.6L11 5M5 11l-1.4 1.4" />
  </svg>
)

export const VaultIcon = ({ size = 14 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <path d="M2.5 3.5h6.8a2 2 0 0 1 2 2v8l-2-1.4-2 1.4v-8a2 2 0 0 0-2-2" />
    <path d="M2.5 3.5v8.2a1.8 1.8 0 0 0 1.8 1.8h5" />
  </svg>
)

export const SearchIcon = ({ size = 12 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <circle cx="7" cy="7" r="4.2" />
    <path d="M10.2 10.2L14 14" />
  </svg>
)

export const RecallIcon = ({ size = 12 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <path d="M8 2.2a4.5 4.5 0 0 1 4.5 4.5c0 1.5-.6 2.5-1.4 3.4-.6.7-.9 1.2-.9 2v1.2H5.8v-1.2c0-.8-.3-1.3-.9-2-.8-.9-1.4-1.9-1.4-3.4A4.5 4.5 0 0 1 8 2.2Z" />
  </svg>
)

export const NoteIcon = ({ size = 12 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <path d="M11.2 2.3l2.5 2.5L6 12.5l-3.2.7.7-3.2 7.7-7.7Z" />
  </svg>
)

export const PageIcon = ({ size = 12 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <path d="M4 1.8h5.5L13 5.3v8.9H4V1.8Z" />
    <path d="M9.5 1.8v3.5H13" />
  </svg>
)

export const ToolIcon = ({ size = 12 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <path d="M9.8 2.4a3.6 3.6 0 0 0-4.5 4.5L2 10.2l1.9 1.9 3.3-3.3a3.6 3.6 0 0 0 4.5-4.5L9.5 6.5 7.6 4.6l2.2-2.2Z" />
  </svg>
)

export const SpeakerIcon = ({ size = 14 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <path d="M2.5 6v4h2.4L8.5 13V3L4.9 6H2.5Z" />
    <path d="M10.8 5.5a3.5 3.5 0 0 1 0 5M12.6 3.8a6 6 0 0 1 0 8.4" />
  </svg>
)

export const SendIcon = ({ size = 15 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <path d="M8 13V3M3.5 7.5 8 3l4.5 4.5" />
  </svg>
)

export const StopIcon = ({ size = 13 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <rect x="3.5" y="3.5" width="9" height="9" rx="1.2" />
  </svg>
)

export const CloseIcon = ({ size = 14 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <path d="M4 4l8 8M12 4l-8 8" />
  </svg>
)

export const PlayIcon = ({ size = 12 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <path d="M5 3.2v9.6L12.5 8 5 3.2Z" />
  </svg>
)

export const ImageIcon = ({ size = 14 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <rect x="2.2" y="3" width="11.6" height="10" rx="1.4" />
    <circle cx="5.6" cy="6.2" r="1" />
    <path d="M3.5 11.6 6.6 8.5l2.1 2.1 1.3-1.3 2.5 2.3" />
  </svg>
)

export const WarnIcon = ({ size = 12 }: IconProps): React.JSX.Element => (
  <svg {...base(size)}>
    <path d="M8 2.2 14.5 13.5h-13L8 2.2Z" />
    <path d="M8 6.5v3.2M8 11.6v.2" />
  </svg>
)

export const PersonIcon = ({ size = 16, className }: IconProps): React.JSX.Element => (
  <svg {...base(size)} className={className}>
    <circle cx="8" cy="5.4" r="2.2" />
    <path d="M3.8 13.2c.8-2.4 2.2-3.6 4.2-3.6s3.4 1.2 4.2 3.6" />
  </svg>
)

export function activityIcon(kind: string): React.JSX.Element {
  switch (kind) {
    case 'search': return <SearchIcon />
    case 'memory-recall': return <RecallIcon />
    case 'memory-save': return <NoteIcon />
    case 'fetch': return <PageIcon />
    default: return <ToolIcon />
  }
}
