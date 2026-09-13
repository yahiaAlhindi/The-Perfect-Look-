import {
  Bell,
  Menu,
  UserRound,
  CalendarDays,
  CheckCircle2,
  CreditCard,
  Loader2,
  Mail,
  Moon,
  Plus,
  Search,
  Sparkles,
  Sun,
} from 'lucide-react'
import { useState } from 'react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import { Skeleton } from '@/components/ui/skeleton'
import { Spinner } from '@/components/ui/spinner'
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import { toast } from '@/components/ui/toaster'
import { EmptyState } from '@/components/feedback/empty-state'
import { ErrorState } from '@/components/feedback/error-state'
import { PageLoader, InlineLoader } from '@/components/feedback/loading'
import { PageHeader } from '@/components/layout/page-header'
import { brand } from '@/config/brand'
import { cn } from '@/lib/utils'

/* ---------------------------------------------------------------------------
 * Page chrome
 * ------------------------------------------------------------------------- */

const tokenDisplay = (name: string) =>
  getComputedStyle(document.documentElement).getPropertyValue(name).trim()

/** Pretty-print an oklch() token for the documentation table. */
function oklchShort(value: string) {
  if (!value) return '—'
  const match = value.match(/oklch\(([\d.]+)[^,]*,[^,]*,[^)]*\)/)
  return match ? `oklch …${match[1]}` : value
}

function Section({
  id,
  title,
  description,
  children,
}: {
  id: string
  title: string
  description: string
  children: React.ReactNode
}) {
  return (
    <section id={id} className="scroll-mt-24 border-t py-10 first:border-t-0">
      <h2 className="text-xl font-bold">{title}</h2>
      <p className="mt-1 mb-6 max-w-2xl text-sm text-muted-foreground">{description}</p>
      {children}
    </section>
  )
}

function DemoCard({
  title,
  hint,
  children,
  className,
}: {
  title: string
  hint?: string
  children: React.ReactNode
  className?: string
}) {
  return (
    <div
      className={cn(
        'rounded-xl border bg-card p-4 flex flex-col gap-3 shadow-sm',
        className,
      )}
    >
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-sm font-medium">{title}</p>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </div>
      {children}
    </div>
  )
}

const navLinks = [
  { href: '#tokens', label: 'Tokens' },
  { href: '#buttons', label: 'Buttons' },
  { href: '#inputs', label: 'Inputs' },
  { href: '#cards', label: 'Cards' },
  { href: '#badges', label: 'Badges' },
  { href: '#overlays', label: 'Overlays' },
  { href: '#feedback', label: 'Feedback' },
  { href: '#layout', label: 'Layout' },
  { href: '#rtl', label: 'RTL' },
]

/* ---------------------------------------------------------------------------
 * Page
 * ------------------------------------------------------------------------- */

export default function DesignSystemPage() {
  const [checked, setChecked] = useState(true)
  const [loading, setLoading] = useState(false)
  const [dark, setDark] = useState(false)
  const [dir, setDir] = useState<'ltr' | 'rtl'>('ltr')

  const toggleDark = () => {
    const next = !dark
    setDark(next)
    document.documentElement.classList.toggle('dark', next)
  }

  const toggleDir = () => {
    const next = dir === 'ltr' ? 'rtl' : 'ltr'
    setDir(next)
    document.documentElement.setAttribute('dir', next)
  }

  const brandName = brand.name
  const BrandMark = brand.mark.icon

  return (
    <div className="min-h-svh bg-background">
      {/* Sticky demo toolbar */}
      <div className="sticky top-0 z-40 border-b bg-background/90 backdrop-blur">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-3">
          <div className="flex items-center gap-2">
            <span className="flex size-8 items-center justify-center rounded-lg bg-brand text-brand-fg">
              <BrandMark aria-hidden="true" className="size-4" />
            </span>
            <div>
              <p className="text-sm font-semibold leading-none">{brandName}</p>
              <p className="text-xs text-muted-foreground">Component Library · T1</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={toggleDir} aria-pressed={dir === 'rtl'}>
              {dir === 'ltr' ? (
                <>
                  <span aria-hidden="true">RTL</span> العربية
                </>
              ) : (
                <>
                  <span aria-hidden="true">LTR</span> English
                </>
              )}
            </Button>
            <Button variant="outline" size="sm" onClick={toggleDark} aria-pressed={dark}>
              {dark ? <Sun aria-hidden="true" /> : <Moon aria-hidden="true" />}
              {dark ? 'Light' : 'Dark'}
            </Button>
          </div>
        </div>
      </div>

      <main className="mx-auto max-w-5xl px-4 pb-20">
        {/* Hero */}
        <div className="py-10 md:py-14">
          <Badge variant="soft" className="mb-4">
            Placeholder brand — swapped from one layer in T46
          </Badge>
          <h1 className="max-w-3xl text-3xl font-bold tracking-tight md:text-5xl">
            {brandName} design system
          </h1>
          <p className="mt-3 max-w-2xl text-base text-muted-foreground md:text-lg">
            Shared tokens and reusable React components for the patient and
            admin apps. Responsive from 360px (PWA phones) to 1280px+ desktops
            with native Arabic/RTL support.
          </p>
          <nav className="mt-6 flex flex-wrap gap-2" aria-label="Component index">
            {navLinks.map((link) => (
              <a
                key={link.href}
                href={link.href}
                className="rounded-md border px-3 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground"
              >
                {link.label}
              </a>
            ))}
          </nav>
        </div>

        {/* ---------------- Tokens ---------------- */}
        <Section
          id="tokens"
          title="Design tokens"
          description="Every colour, radius, and font flows from src/styles/tokens.css — the single swap layer. Components never hard-code a value."
        >
          <p className="text-sm text-muted-foreground">
            Current brand anchor: <code className="text-foreground">{oklchShort(tokenDisplay('--brand'))}</code>{' '}
            · Font (AR): <code className="text-foreground">'{brand.fonts.arabic}'</code>
          </p>
          <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-5">
            {(['50', '100', '200', '300', '400', '500', '600', '700', '800', '900', '950'] as const).map(
              (step) => (
                <div key={step} className="overflow-hidden rounded-lg border">
                  <div
                    className="h-10"
                    style={{ backgroundColor: `var(--brand-${step})` }}
                  />
                  <p className="flex justify-between px-2 py-1 text-xs">
                    <span>brand-{step}</span>
                    <span className="text-muted-foreground">
                      {oklchShort(tokenDisplay(`--brand-${step}`))}
                    </span>
                  </p>
                </div>
              ),
            )}
          </div>

          <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
            {(['primary', 'secondary', 'muted', 'accent', 'destructive', 'success', 'warning', 'info'] as const).map(
              (semantic) => (
                <div key={semantic} className="overflow-hidden rounded-lg border">
                  <div className="h-10" style={{ backgroundColor: `var(--${semantic})` }} />
                  <p className="flex justify-between px-2 py-1 text-xs">
                    <span>{semantic}</span>
                    <span className="text-muted-foreground">
                      {oklchShort(tokenDisplay(`--${semantic}`))}
                    </span>
                  </p>
                </div>
              ),
            )}
          </div>

          <div className="mt-6 grid gap-3 sm:grid-cols-2">
            <DemoCard title="Type ramps" hint="--font-sans / --font-arabic">
              <p className="text-2xl font-bold">صحة وجمال 123</p>
              <p className="text-base">Health &amp; beauty 123 — Lorem ipsum dolor sit amet.</p>
              <p className="text-sm text-muted-foreground">
                Muted copy guides scale; <code>text-sm</code> is the default body size.
              </p>
            </DemoCard>
            <DemoCard title="Shape" hint="--radius">
              <div className="flex flex-wrap gap-2">
                {(['sm', 'md', 'lg', 'xl'] as const).map((step) => (
                  <span
                    key={step}
                    className={cn(
                      'flex size-14 items-end justify-center border pb-1 text-[10px] text-muted-foreground',
                      step === 'sm' && 'rounded-sm',
                      step === 'md' && 'rounded-md',
                      step === 'lg' && 'rounded-lg',
                      step === 'xl' && 'rounded-xl',
                    )}
                  >
                    {step}
                  </span>
                ))}
              </div>
            </DemoCard>
          </div>
        </Section>

        {/* ---------------- Buttons ---------------- */}
        <Section
          id="buttons"
          title="Buttons"
          description="Variants, sizes, icons, loading, disabled, and asChild links."
        >
          <div className="grid gap-3 md:grid-cols-2">
            <DemoCard title="Variants">
              <div className="flex flex-wrap items-center gap-2">
                <Button>Default</Button>
                <Button variant="secondary">Secondary</Button>
                <Button variant="outline">Outline</Button>
                <Button variant="ghost">Ghost</Button>
                <Button variant="destructive">Delete</Button>
                <Button variant="link">Link</Button>
              </div>
            </DemoCard>
            <DemoCard title="Sizes">
              <div className="flex flex-wrap items-center gap-2">
                <Button size="sm">Small</Button>
                <Button>Default</Button>
                <Button size="lg">Large</Button>
                <Button size="icon" aria-label="Menu">
                  <Menu />
                </Button>
                <Button size="icon" aria-label="Profile">
                  <UserRound />
                </Button>
              </div>
            </DemoCard>
            <DemoCard title="Icons & loading">
              <div className="flex flex-wrap items-center gap-2">
                <Button>
                  <Plus /> New appointment
                </Button>
                <Button
                  loading={loading}
                  onClick={() => {
                    setLoading(true)
                    setTimeout(() => setLoading(false), 1800)
                  }}
                >
                  Save changes
                </Button>
                <Button variant="outline" disabled>
                  Disabled
                </Button>
              </div>
              <p className="text-xs text-muted-foreground">
                Pass <code>loading</code> — a spinner is injected automatically.
              </p>
            </DemoCard>
            <DemoCard title="asChild (link buttons)">
              <div className="flex flex-wrap items-center gap-2">
                <Button asChild>
                  <a href="#rtl">Anchor button</a>
                </Button>
                <Button asChild variant="outline">
                  <a href="#layout">Outline link</a>
                </Button>
              </div>
            </DemoCard>
          </div>
        </Section>

        {/* ---------------- Inputs ---------------- */}
        <Section
          id="inputs"
          title="Form controls"
          description="Label, input, textarea, select, checkbox — all keyboard/focus accessible and RTL-ready."
        >
          <div className="grid gap-3 md:grid-cols-2">
            <DemoCard title="Text inputs">
              <div className="grid gap-4">
                <div className="grid gap-2">
                  <Label htmlFor="demo-name">Full name</Label>
                  <Input id="demo-name" placeholder="e.g. Sara Al Maktoum" />
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="demo-email">Email</Label>
                  <Input id="demo-email" type="email" placeholder="you@example.com" defaultValue="sara@example.com" />
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="demo-search">With icon</Label>
                  <div className="relative">
                    <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                    <Input id="demo-search" className="ps-9" placeholder="Search services…" />
                  </div>
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="demo-invalid">Invalid state</Label>
                  <Input id="demo-invalid" aria-invalid="true" defaultValue="not-an-email" />
                  <p className="text-xs text-destructive">Please enter a valid email.</p>
                </div>
              </div>
            </DemoCard>

            <DemoCard title="Textarea & numbers">
              <div className="grid gap-4">
                <div className="grid gap-2">
                  <Label htmlFor="demo-notes">Booking notes</Label>
                  <Textarea id="demo-notes" placeholder="Anything the clinic should know…" />
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="demo-mobile">Mobile (AE)</Label>
                  <Input id="demo-mobile" inputMode="tel" placeholder="+971 5X XXX XXXX" />
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="demo-date">Date</Label>
                  <Input id="demo-date" type="date" />
                </div>
              </div>
            </DemoCard>

            <DemoCard title="Select">
              <div className="grid gap-4">
                <div className="grid gap-2">
                  <Label htmlFor="demo-service">Service</Label>
                  <Select defaultValue="facial">
                    <SelectTrigger id="demo-service" className="w-full">
                      <SelectValue placeholder="Choose a service" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="consult">Consultation</SelectItem>
                      <SelectItem value="facial">Facial treatment</SelectItem>
                      <SelectItem value="laser">Laser session</SelectItem>
                      <SelectItem value="inject">Injectables</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="grid gap-2">
                  <Label>Size sm</Label>
                  <Select defaultValue="dubai">
                    <SelectTrigger size="sm" className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="dubai">Dubai</SelectItem>
                      <SelectItem value="sharjah">Sharjah</SelectItem>
                      <SelectItem value="dha">DHA</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
            </DemoCard>

            <DemoCard title="Checkbox & preview">
              <div className="grid gap-4">
                <div className="flex items-center gap-2">
                  <Checkbox id="demo-consent" checked={checked} onCheckedChange={(v) => setChecked(Boolean(v))} />
                  <Label htmlFor="demo-consent" className="font-normal">
                    I agree to the clinic’s privacy policy
                  </Label>
                </div>
                <div className="flex items-center gap-2">
                  <Checkbox id="demo-news" defaultChecked={false} />
                  <Label htmlFor="demo-news" className="font-normal">
                    Receive appointment reminders by SMS
                  </Label>
                </div>
                <div className="flex items-center gap-2">
                  <Checkbox id="demo-disabled" disabled />
                  <Label htmlFor="demo-disabled" className="font-normal text-muted-foreground">
                    Disabled option
                  </Label>
                </div>
                <div className="flex items-center gap-2 rounded-lg border bg-muted/40 px-3 py-2 text-xs text-muted-foreground">
                  <CheckCircle2 className="size-4 text-success" aria-hidden="true" />
                  Checkbox-indicator uses the <code>brand</code> token when checked.
                </div>
              </div>
            </DemoCard>
          </div>
        </Section>

        {/* ---------------- Cards ---------------- */}
        <Section
          id="cards"
          title="Cards"
          description="Surface container for lists, summaries and dialogs."
        >
          <div className="grid gap-3 md:grid-cols-2">
            <DemoCard title="Service card" hint="patient booking">
              <Card>
                <CardHeader>
                  <div className="flex items-start justify-between gap-2">
                    <CardTitle>Signature Facial</CardTitle>
                    <Badge variant="success" className="mt-0.5">
                      Available
                    </Badge>
                  </div>
                  <CardDescription>60 minutes · AED 350</CardDescription>
                </CardHeader>
                <CardContent>
                  <p className="text-sm leading-relaxed">
                    Deep-cleansing facial tailored to your skin type, including a
                    relaxing scalp and shoulder massage.
                  </p>
                </CardContent>
                <CardFooter>
                  <Button size="sm" className="me-auto">
                    <CalendarDays /> Book
                  </Button>
                  <Badge variant="secondary">3 slots today</Badge>
                </CardFooter>
              </Card>
            </DemoCard>

            <DemoCard title="Account card" hint="admin / patient">
              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                    <CreditCard aria-hidden="true" /> Payment methods
                  </CardTitle>
                  <CardDescription>Manage how you pay for appointments.</CardDescription>
                </CardHeader>
                <CardContent className="space-y-3">
                  <div className="flex items-center justify-between rounded-lg border px-3 py-2">
                    <span className="text-sm">Visa •••• 4242</span>
                    <Badge variant="success">Default</Badge>
                  </div>
                  <div className="flex items-center justify-between rounded-lg border px-3 py-2">
                    <span className="text-sm">Visa •••• 1881</span>
                    <Badge variant="warning">Expiring</Badge>
                  </div>
                </CardContent>
                <CardFooter>
                  <Button variant="outline" size="sm" className="w-full">
                    <Plus /> Add payment method
                  </Button>
                </CardFooter>
              </Card>
            </DemoCard>
          </div>
        </Section>

        {/* ---------------- Badges ---------------- */}
        <Section
          id="badges"
          title="Badges"
          description="Small status/label chips. Variants map to semantic status tokens."
        >
          <div className="grid gap-3 md:grid-cols-2">
            <DemoCard title="Variants">
              <div className="flex flex-wrap items-center gap-2">
                <Badge>Default</Badge>
                <Badge variant="secondary">Secondary</Badge>
                <Badge variant="outline">Outline</Badge>
                <Badge variant="soft">Soft brand</Badge>
                <Badge variant="destructive">Destructive</Badge>
                <Badge variant="success">Success</Badge>
                <Badge variant="warning">Pending</Badge>
                <Badge variant="info">Info</Badge>
              </div>
            </DemoCard>
            <DemoCard title="Semantic usage" hint="appointment lifecycle">
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant="success">
                  <CheckCircle2 /> Confirmed
                </Badge>
                <Badge variant="warning">
                  <Loader2 /> Pending
                </Badge>
                <Badge variant="info">
                  <Bell /> Reminder sent
                </Badge>
                <Badge variant="destructive">Cancelled</Badge>
                <Badge variant="secondary">Rescheduled</Badge>
              </div>
            </DemoCard>
          </div>
        </Section>

        {/* ---------------- Overlays ---------------- */}
        <Section
          id="overlays"
          title="Overlays"
          description="Dialog, tabs, and toast notifications."
        >
          <div className="grid gap-3 md:grid-cols-2">
            <DemoCard title="Dialog" hint="focus-trapped, Esc-dismissible">
              <Dialog>
                <DialogTrigger asChild>
                  <Button>
                    <Sparkles /> New appointment
                  </Button>
                </DialogTrigger>
                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>Book an appointment</DialogTitle>
                    <DialogDescription>
                      Pick a service and time — the clinic confirms by SMS.
                    </DialogDescription>
                  </DialogHeader>
                  <div className="grid gap-4 py-2">
                    <div className="grid gap-2">
                      <Label htmlFor="dlg-service">Service</Label>
                      <Select defaultValue="facial">
                        <SelectTrigger id="dlg-service" className="w-full">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="consult">Consultation</SelectItem>
                          <SelectItem value="facial">Facial treatment</SelectItem>
                          <SelectItem value="laser">Laser session</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="grid gap-2">
                      <Label htmlFor="dlg-date">Preferred date</Label>
                      <Input id="dlg-date" type="date" />
                    </div>
                  </div>
                  <DialogFooter>
                    <Button variant="secondary" type="button" onClick={() => toast.info('No changes made')}>
                      Cancel
                    </Button>
                    <Button type="button" onClick={() => toast.success('Request sent — we’ll confirm shortly')}>
                      Request booking
                    </Button>
                  </DialogFooter>
                </DialogContent>
              </Dialog>
            </DemoCard>

            <DemoCard title="Tabs" hint="touch-friendly on narrow phones">
              <Tabs defaultValue="upcoming">
                <TabsList className="w-full overflow-x-auto">
                  <TabsTrigger value="upcoming">Upcoming</TabsTrigger>
                  <TabsTrigger value="history">History</TabsTrigger>
                  <TabsTrigger value="cancelled">Cancelled</TabsTrigger>
                </TabsList>
                <TabsContent value="upcoming" className="rounded-lg border p-3 text-sm">
                  <p className="flex items-center gap-2 text-muted-foreground">
                    <CalendarDays className="size-4" /> Saturday 14:30 — Signature Facial
                  </p>
                </TabsContent>
                <TabsContent value="history" className="rounded-lg border p-3 text-sm">
                  <p className="text-muted-foreground">Your past appointments will appear here.</p>
                </TabsContent>
                <TabsContent value="cancelled" className="rounded-lg border p-3 text-sm">
                  <p className="text-muted-foreground">Cancelled appointments land in this tab.</p>
                </TabsContent>
              </Tabs>
            </DemoCard>
          </div>

          <DemoCard title="Toasts" className="mt-3">
            <div className="flex flex-wrap items-center gap-2">
              <Button onClick={() => toast.success('Appointment booked for Saturday 14:30')}>
                Success toast
              </Button>
              <Button variant="secondary" onClick={() => toast.error('Could not load services. Please retry.')}>
                Error toast
              </Button>
              <Button variant="outline" onClick={() => toast.info('Reminder sent to +971 5X XXX XXXX')}>
                Info toast
              </Button>
              <Button
                variant="outline"
                onClick={() =>
                  toast.promise(Promise.resolve(), {
                    loading: 'Saving changes…',
                    success: 'Saved',
                    error: 'Save failed',
                  })
                }
              >
                Promise toast
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">
              Rendered by <code>&lt;Toaster /&gt;</code> in <code>main.tsx</code>.
            </p>
          </DemoCard>
        </Section>

        {/* ---------------- Feedback ---------------- */}
        <Section
          id="feedback"
          title="Loading & empty states"
          description="Skeletons, spinners, empty, and error states for async data."
        >
          <div className="grid gap-3 md:grid-cols-2">
            <DemoCard title="Spinners" hint="tokens-sized">
              <div className="flex flex-wrap items-center gap-3">
                <Spinner size="sm" />
                <Spinner />
                <Spinner size="lg" />
                <Spinner size="xl" />
              </div>
            </DemoCard>
            <DemoCard title="Skeleton card" hint="list placeholder">
              <div className="grid gap-3 rounded-lg border p-3">
                <div className="flex items-center gap-3">
                  <Skeleton className="size-10 rounded-full" />
                  <div className="grid gap-1.5 flex-1">
                    <Skeleton className="h-3.5 w-1/3" />
                    <Skeleton className="h-3 w-1/2" />
                  </div>
                </div>
                <Skeleton className="h-8 w-full" />
                <Skeleton className="h-8 w-2/3" />
              </div>
            </DemoCard>

            <DemoCard title="Empty state">
              <EmptyState
                icon={CalendarDays}
                title="No upcoming appointments"
                description="When you book a visit it will show up here with reminders and history."
                action={
                  <>
                    <Button>
                      <Plus /> Book a service
                    </Button>
                    <Button variant="ghost">View services</Button>
                  </>
                }
              />
            </DemoCard>

            <DemoCard title="Error state">
              <ErrorState
                message="We couldn’t reach the server (net-http-502). Your data is safe."
                onRetry={() => toast.info('Retrying…')}
              />
            </DemoCard>
          </div>

          <div className="mt-3 grid gap-3 md:grid-cols-2">
            <InlineLoader label="Loading services…" />
          </div>
        </Section>

        {/* ---------------- Layout ---------------- */}
        <Section
          id="layout"
          title="Page headers & layout"
          description="Sticky headers, page heading blocks, and full-page loading."
        >
          <DemoCard title="PageHeader" hint="stacks on mobile, row on md+">
            <PageHeader
              eyebrow="Patient · Appointments"
              title="My appointments"
              description="Manage upcoming visits, reschedule, or cancel with 24h notice."
              actions={
                <>
                  <Button variant="outline" size="sm">
                    Reschedule
                  </Button>
                  <Button size="sm">
                    <Plus /> Book new
                  </Button>
                </>
              }
            />
          </DemoCard>

          <div className="mt-3 grid gap-3 md:grid-cols-2">
            <DemoCard title="PageLoader" hint="min-h-svh for PWA phones">
              <div className="rounded-lg border bg-muted/20">
                <PageLoader />
              </div>
            </DemoCard>
            <DemoCard title="Dividers" hint="rtl-safe">
              <div className="flex flex-col gap-4">
                <Separator />
                <p className="text-sm text-muted-foreground">A horizontal separator above.</p>
                <div className="flex items-center gap-4">
                  <span className="text-sm">Start</span>
                  <Separator orientation="vertical" className="h-6" />
                  <span className="text-sm">End</span>
                </div>
              </div>
            </DemoCard>
          </div>
        </Section>

        {/* ---------------- RTL ---------------- */}
        <Section
          id="rtl"
          title="Arabic / RTL"
          description="Toggle direction from the toolbar. Layout flips via the dir attribute; logical properties keep icons and text aligned."
        >
          <DemoCard title="Live example">
            <p className="text-base leading-relaxed">
              {dir === 'rtl'
                ? 'هذا هو مثال مباشر للعرض من اليمين إلى اليسار. جميع المكوّنات تتكيف تلقائياً مع اتجاه الصفحة، بما فيها الأزرار والقوائم المنسدلة.'
                : 'This is a live right-to-left demo. Flip the toggle in the toolbar to see components reflow using logical properties.'}
            </p>
            <div className="flex flex-wrap items-center gap-2">
              <Button>
                <Plus /> {dir === 'rtl' ? 'حجز موعد' : 'Book appointment'}
              </Button>
              <Button variant="outline">
                <Mail /> {dir === 'rtl' ? 'تواصل معنا' : 'Contact us'}
              </Button>
            </div>
          </DemoCard>
        </Section>
      </main>

      <footer className="border-t py-6 text-center text-xs text-muted-foreground">
        The Perfect Look — placeholder design system (T1). Approved brand assets apply in T46.
      </footer>
    </div>
  )
}