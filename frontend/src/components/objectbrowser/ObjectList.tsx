import { Search } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { ScrollArea } from '@/components/ui/scroll-area'
import { ObjectListItem } from './ObjectListItem'
import type { ModelType } from './types'

type AnyItem = { id: string; name?: string }

function matchesSearch(item: AnyItem, query: string): boolean {
  if (!query) return true
  const q = query.toLowerCase()
  return (
    (item.id ?? '').toLowerCase().includes(q) ||
    (item.name ?? '').toLowerCase().includes(q)
  )
}

interface ObjectListProps {
  type: ModelType
  items: AnyItem[]
  selectedId: string | null
  searchQuery: string
  onSearchChange: (q: string) => void
  onSelect: (id: string) => void
}

export function ObjectList({ type, items, selectedId, searchQuery, onSearchChange, onSelect }: ObjectListProps) {
  const filtered = items.filter(item => matchesSearch(item, searchQuery))

  return (
    <div className="flex flex-col h-full border-r">
      {/* Search */}
      <div className="p-2 border-b shrink-0">
        <div className="relative">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 size-3.5 text-muted-foreground" />
          <Input
            value={searchQuery}
            onChange={e => onSearchChange(e.target.value)}
            placeholder="Search…"
            className="h-8 pl-8 text-xs"
          />
        </div>
        <p className="text-[10px] text-muted-foreground mt-1.5 px-1">
          {filtered.length} of {items.length}
        </p>
      </div>

      {/* List */}
      <ScrollArea key={type} className="flex-1">
        {filtered.length === 0 ? (
          <div className="p-6 text-center text-sm text-muted-foreground">
            {searchQuery ? 'No results' : 'No items'}
          </div>
        ) : (
          filtered.map(item => (
            <ObjectListItem
              key={item.id}
              type={type}
              item={item as Parameters<typeof ObjectListItem>[0]['item']}
              selected={item.id === selectedId}
              onClick={() => onSelect(item.id)}
            />
          ))
        )}
      </ScrollArea>
    </div>
  )
}
