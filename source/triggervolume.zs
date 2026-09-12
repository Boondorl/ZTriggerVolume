class MyProjectTriggerVolume : Actor
{
	enum ETriggerVolumeFlags
	{
		TVF_PLAYER				= 1,
		TVF_MONSTER				= 1 << 1,
		TVF_REPEATABLE			= 1 << 2,
		TVF_ON_ENTER			= 1 << 3,
		TVF_ON_EXIT				= 1 << 4,
		TVF_CONTINUOUS			= 1 << 5,
		TVF_DONT_STACK			= 1 << 6,
		TVF_VOLUME_IS_CALLER	= 1 << 7,
		TVF_STATIC_ACTOR		= 1 << 8,

		TVF_CAN_TRIGGER			= TVF_PLAYER | TVF_MONSTER | TVF_STATIC_ACTOR,
		TVF_HAS_TRIGGER_TYPE	= TVF_ON_ENTER | TVF_CONTINUOUS | TVF_ON_EXIT,
	}

	enum EScriptType
	{
		ST_ENTER,
		ST_CONTINUOUS,
		ST_EXIT,
	}

	enum ETriggerVolumeArgs
	{
		ARG_SCRIPT,
		ARG_RADIUS,
		ARG_HEIGHT,
		ARG_FLAGS,
	}

	private Array<Actor> _colliders;
	private Array<Actor> _ignore;

	int user_OnEnter;
	String user_OnEnterName;
	int user_OnContinuous;
	String user_OnContinuousName;
	int user_OnExit;
	String user_OnExitName;
	int user_Arg1, user_Arg2, user_Arg3;

	Default
	{
		//$Title "Trigger Volume"
		//$Category "Map Control"
		//$Arg0 "Script"
		//$Arg0Str
		//$Arg0Tooltip "The custom user variables should be used if more control is needed."
		//$Arg1 "Radius"
		//$Arg1Default 32
		//$Arg1Type 23
		//$Arg2 "Height"
		//$Arg2Default 64
		//$Arg2Type 24
		//$Arg3 "Flags"
		//$Arg3Enum { 1 = "Players can trigger"; 2 = "Monsters can trigger"; 256 = "Static Actors can trigger"; 4 = "Repeatable"; 8 = "Trigger on actor entering"; 16 = "Trigger on actor exiting"; 32 = "Continously trigger while actor colliding"; 64 = "Don't stack trigger calls"; 128 = "Set volume as script caller"; }
		//$Arg3Default 9
		//$Arg3Type 12
		//$NotAngled

		Radius 32.0;
		Height 0.0;
		FloatBobPhase 0u;

		+SYNCHRONIZED
		+DONTBLAST
		+NOTONAUTOMAP
		+NOSECTOR
		+SOLID
		+NONSHOOTABLE
	}

	override void MarkPrecacheSounds() {}

	override void BeginPlay()
	{
		Super.BeginPlay();

		ChangeStatNum(MAX_STATNUM);
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();

		A_SetSize(Args[ARG_RADIUS], Args[ARG_HEIGHT]);

		if (!IsValid())
		{
			String error = String.Format("\cRWarning: Volume trigger at (%d, %d, %d) ", Pos.X, Pos.Y, Pos.Z);
			if (TID)
				error.AppendFormat("with tid %d ", TID);

			if (!(Args[ARG_FLAGS] & TVF_CAN_TRIGGER))
				error.AppendFormat("cannot be triggered.");
			else if (!(Args[ARG_FLAGS] & TVF_HAS_TRIGGER_TYPE))
				error.AppendFormat("has no trigger type.");
			else if (!HasScript())
				error.AppendFormat("is missing a script.");

			Console.PrintF("%s", error);
		}
	}

	override void Activate(Actor activator)
	{
		bDormant = false;
	}

	override void Deactivate(Actor deactivator)
	{
		bDormant = true;

		_colliders.Clear();
		_ignore.Clear();
	}

	override void Tick()
	{
		if (bDormant)
			return;

		for (int i; i < _ignore.Size(); ++i)
		{
			if (!_ignore[i] || IsDead(_ignore[i]) || !IsColliding(_ignore[i]))
			{
				if (!(Args[ARG_FLAGS] & TVF_DONT_STACK) || _ignore.Size() == 1)
				{
					if (Args[ARG_FLAGS] & TVF_ON_EXIT)
						Level.ExecuteSpecial(ACS_ExecuteAlways, GetCaller(_ignore[i]), null, 0, GetScript(ST_EXIT), 0, user_Arg1, user_Arg2, user_Arg3);

					if (!(Args[ARG_FLAGS] & TVF_REPEATABLE))
					{
						Destroy();
						return;
					}
				}

				_ignore.Delete(i--);
			}
			else if ((Args[ARG_FLAGS] & TVF_CONTINUOUS) && (!(Args[ARG_FLAGS] & TVF_DONT_STACK) || i == 0))
			{
				Level.ExecuteSpecial(ACS_ExecuteAlways, GetCaller(_ignore[i]), null, 0, GetScript(ST_CONTINUOUS), 0, user_Arg1, user_Arg2, user_Arg3);
			}
		}

		for (int i; i < _colliders.Size(); ++i)
		{
			if (!_colliders[i] || IsDead(_colliders[i]) || !IsColliding(_colliders[i]))
				continue;

			if (!(Args[ARG_FLAGS] & TVF_DONT_STACK) || !_ignore.Size())
			{
				if (Args[ARG_FLAGS] & TVF_ON_ENTER)
					Level.ExecuteSpecial(ACS_ExecuteAlways, GetCaller(_colliders[i]), null, 0, GetScript(ST_ENTER), 0, user_Arg1, user_Arg2, user_Arg3);

				if (!(Args[ARG_FLAGS] & (TVF_CONTINUOUS|TVF_ON_EXIT)) && !(Args[ARG_FLAGS] & TVF_REPEATABLE))
				{
					Destroy();
					return;
				}
			}

			_ignore.Push(_colliders[i]);
		}

		_colliders.Clear();
	}

	override bool CanCollideWith(Actor other, bool passive)
	{
		if (!bDormant && passive && CanTrigger(other))
			_colliders.Push(other);

		return false;
	}

	protected clearscope Vector3, Vector3 BoundingBox(readonly<Actor> mo, Sector from = null) const
	{
		Vector3 pos = from ? mo.PosRelative(from) : mo.Pos;
		Vector3 minBox = pos - (mo.Radius, mo.Radius, 0.0);
		Vector3 maxBox = pos + (mo.Radius, mo.Radius, mo.Height);

		return minBox, maxBox;
	}

	protected clearscope bool IsColliding(readonly<Actor> dest) const
	{
		let [oMin, oMax] = BoundingBox(self);
		let [dMin, dMax] = BoundingBox(dest, self.CurSector);
		
		return (oMin.x <= dMax.x && oMax.x >= dMin.x)
				&& (oMin.y <= dMax.y && oMax.y >= dMin.y)
				&& (oMin.z <= dMax.z && oMax.z >= dMin.z);
	}

	private bool IsDead(Actor mo)
	{
		return (mo.bIsMonster || mo.Player) && mo.bKilled;
	}

	private Actor GetCaller(Actor mo)
	{
		return (Args[ARG_FLAGS] & TVF_VOLUME_IS_CALLER) ? Actor(self) : mo;
	}

	private int GetScript(EScriptType type)
	{
		if (Args[ARG_SCRIPT])
			return Args[ARG_SCRIPT];

		int id;
		Name nameId;

		switch (type)
		{
		case ST_ENTER:
			id = user_OnEnter;
			nameID = user_OnEnterName;
			break;

		case ST_CONTINUOUS:
			id = user_OnContinuous;
			nameID = user_OnContinuousName;
			break;

		case ST_EXIT:
			id = user_OnExit;
			nameID = user_OnExitName;
			break;
		}

		return id ? id : -int(nameID);
	}

	private bool HasScript()
	{
		if (Args[ARG_SCRIPT])
			return true;

		if (((Args[ARG_FLAGS] & TVF_ON_ENTER) && !GetScript(ST_ENTER))
			|| ((Args[ARG_FLAGS] & TVF_CONTINUOUS) && !GetScript(ST_CONTINUOUS))
			|| ((Args[ARG_FLAGS] & TVF_ON_EXIT) && !GetScript(ST_EXIT)))
		{
			return false;
		}

		return true;
	}

	private bool IsValid()
	{
		return (Args[ARG_FLAGS] & TVF_CAN_TRIGGER) && (Args[ARG_FLAGS] & TVF_HAS_TRIGGER_TYPE) && HasScript();
	}

	private bool CanTrigger(Actor other)
	{
		if (!IsValid())
			return false;

		// Predicting can actually happen here since players will be activating the collision check.
		if (!other || (other.Player && (other.Player.Cheats & CF_PREDICTING)) || IsDead(other)
			|| _colliders.Find(other) < _colliders.Size() || _ignore.Find(other) < _ignore.Size())
		{
			return false;
		}

		 return ((Args[ARG_FLAGS] & TVF_PLAYER) && other.Player) || ((Args[ARG_FLAGS] & TVF_MONSTER) && other.bIsMonster)
				|| ((Args[ARG_FLAGS] & TVF_STATIC_ACTOR) && !other.bIsMonster && !other.Player && !other.bMissile);
	}
}
